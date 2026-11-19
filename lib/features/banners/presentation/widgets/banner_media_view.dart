import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/banner_repository.dart';
import '../../data/models/banner_models.dart';

typedef BannerMediaUrlResolver = Future<String?> Function(
  BannerMedia? media, {
  bool forceRefreshFromStorage,
});

/// Reusable media renderer for a single [BannerSlide] (image or video).
/// Handles responsive media/poster selection, muted video autoplay, app
/// lifecycle pause/resume, controller disposal, and expired URL recovery.
class BannerMediaView extends StatefulWidget {
  final BannerSlide slide;
  final bool isDesktop;
  final bool isActiveSlide;
  final bool autoplay;
  final bool loopVideo;
  final BannerMedia? topLevelDesktopPoster;
  final BannerMedia? topLevelMobilePoster;
  final bool allowTopLevelPosterFallback;
  final BannerMediaUrlResolver? mediaUrlResolver;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onMediaError;

  const BannerMediaView({
    super.key,
    required this.slide,
    required this.isDesktop,
    required this.isActiveSlide,
    required this.autoplay,
    required this.loopVideo,
    this.topLevelDesktopPoster,
    this.topLevelMobilePoster,
    this.allowTopLevelPosterFallback = false,
    this.mediaUrlResolver,
    this.onVideoCompleted,
    this.onMediaError,
  });

  @override
  State<BannerMediaView> createState() => _BannerMediaViewState();
}

class _BannerMediaViewState extends State<BannerMediaView>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  String? _resolvedMediaUrl;
  String? _resolvedPosterUrl;
  bool _isVideoInitialized = false;
  bool _hasError = false;
  bool _retriedStorageRefresh = false;
  bool _completionNotified = false;
  int _initEpoch = 0;

  BannerMedia? get _activeMedia =>
      widget.slide.selectMedia(isDesktop: widget.isDesktop);

  BannerMedia? get _activePoster => widget.slide.selectPoster(
        isDesktop: widget.isDesktop,
        topLevelDesktopPoster: widget.topLevelDesktopPoster,
        topLevelMobilePoster: widget.topLevelMobilePoster,
        allowTopLevelPosterFallback: widget.allowTopLevelPosterFallback,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepareMedia(forceRefresh: false);
  }

  @override
  void didUpdateWidget(covariant BannerMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final mediaChanged = oldWidget.slide.id != widget.slide.id ||
        oldWidget.isDesktop != widget.isDesktop ||
        oldWidget.slide.mediaType != widget.slide.mediaType ||
        oldWidget.slide.selectMedia(isDesktop: oldWidget.isDesktop)?.url !=
            _activeMedia?.url;

    if (mediaChanged) {
      _retriedStorageRefresh = false;
      _disposeVideoController();
      _prepareMedia(forceRefresh: false);
      return;
    }

    if (widget.slide.mediaType == BannerMediaType.video) {
      if (!oldWidget.isActiveSlide && widget.isActiveSlide) {
        if (_videoController == null) {
          _prepareMedia(forceRefresh: false);
        } else if (_isVideoInitialized) {
          _syncVideoPlayback();
        }
      } else if (oldWidget.isActiveSlide && !widget.isActiveSlide) {
        // Dispose inactive slide video controllers to prevent overlapping decoders
        _disposeVideoController();
      } else if (oldWidget.loopVideo != widget.loopVideo ||
          oldWidget.autoplay != widget.autoplay) {
        _syncVideoPlayback();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _videoController;
    if (controller == null || !_isVideoInitialized) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActiveSlide && widget.autoplay) {
        controller.play();
      }
    }
  }

  Future<String?> _resolveUrl(
    BannerMedia? media, {
    bool forceRefresh = false,
  }) async {
    if (media == null || !media.isUsable) return null;
    if (widget.mediaUrlResolver != null) {
      return widget.mediaUrlResolver!(
        media,
        forceRefreshFromStorage: forceRefresh,
      );
    }
    return media.hasUrl ? media.url!.trim() : null;
  }

  Future<void> _prepareMedia({required bool forceRefresh}) async {
    final epoch = ++_initEpoch;
    final media = _activeMedia;
    final poster = _activePoster;

    if (mounted) {
      setState(() {
        _hasError = false;
        if (forceRefresh) {
          _isVideoInitialized = false;
        }
      });
    }

    final posterUrl = await _resolveUrl(poster, forceRefresh: false);
    final mediaUrl = await _resolveUrl(media, forceRefresh: forceRefresh);

    if (!mounted || epoch != _initEpoch) return;

    setState(() {
      _resolvedPosterUrl = posterUrl;
      _resolvedMediaUrl = mediaUrl;
    });

    if (mediaUrl == null || mediaUrl.isEmpty) {
      setState(() => _hasError = true);
      widget.onMediaError?.call();
      return;
    }

    if (widget.slide.mediaType == BannerMediaType.video && widget.isActiveSlide) {
      await _initializeVideo(mediaUrl, epoch);
    }
  }

  Future<void> _initializeVideo(String url, int epoch) async {
    _disposeVideoController();
    _completionNotified = false;

    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      if (mounted && epoch == _initEpoch) {
        setState(() => _hasError = true);
        widget.onMediaError?.call();
      }
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(uri);
      _videoController = controller;
      await controller.initialize();
      if (!mounted || epoch != _initEpoch) {
        await controller.dispose();
        return;
      }

      // Mute when autoplaying to comply with browser/mobile autoplay policies
      await controller.setVolume(widget.autoplay ? 0.0 : 1.0);
      await controller.setLooping(widget.loopVideo);
      controller.addListener(_handleVideoTick);

      setState(() {
        _isVideoInitialized = true;
        _hasError = false;
      });

      if (widget.isActiveSlide && widget.autoplay) {
        try {
          await controller.play();
        } catch (e) {
          // Browsers may still block unmuted/unexpected autoplay; keep poster/frame visible
          debugPrint('[BannerMediaView] Autoplay play() warning: $e');
        }
      }
    } catch (e) {
      debugPrint('[BannerMediaView] Video init error for $url: $e');
      _disposeVideoController();
      if (!mounted || epoch != _initEpoch) return;

      // Attempt one storagePath download-URL refresh in case the URL expired
      if (!_retriedStorageRefresh && (_activeMedia?.hasStoragePath ?? false)) {
        _retriedStorageRefresh = true;
        await _prepareMedia(forceRefresh: true);
        return;
      }

      setState(() => _hasError = true);
      widget.onMediaError?.call();
    }
  }

  void _syncVideoPlayback() {
    final controller = _videoController;
    if (controller == null || !_isVideoInitialized) return;

    controller.setLooping(widget.loopVideo);
    if (widget.isActiveSlide && widget.autoplay) {
      controller.setVolume(0.0);
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _handleVideoTick() {
    final controller = _videoController;
    if (controller == null || !mounted) return;

    final value = controller.value;
    if (value.hasError && !_hasError) {
      setState(() => _hasError = true);
      widget.onMediaError?.call();
      return;
    }

    if (!widget.loopVideo &&
        value.isInitialized &&
        !_completionNotified &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 150)) {
      _completionNotified = true;
      widget.onVideoCompleted?.call();
    }
  }

  void _disposeVideoController() {
    final controller = _videoController;
    _videoController = null;
    _isVideoInitialized = false;
    if (controller != null) {
      controller.removeListener(_handleVideoTick);
      controller.pause();
      controller.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initEpoch++;
    _disposeVideoController();
    super.dispose();
  }

  Widget _buildNeutralPlaceholder({bool showSpinner = false}) {
    return Container(
      color: AppColors.secondaryBackground,
      alignment: Alignment.center,
      child: showSpinner
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryGreen,
              ),
            )
          : const Icon(
              Icons.eco_outlined,
              size: 32,
              color: AppColors.textMuted,
            ),
    );
  }

  Widget _buildPosterOrPlaceholder({required bool showSpinnerWhenNoPoster}) {
    final posterUrl = _resolvedPosterUrl;
    if (posterUrl != null && posterUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: posterUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => _buildNeutralPlaceholder(showSpinner: false),
        errorWidget: (_, __, ___) =>
            _buildNeutralPlaceholder(showSpinner: showSpinnerWhenNoPoster),
      );
    }
    return _buildNeutralPlaceholder(showSpinner: showSpinnerWhenNoPoster);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slide.mediaType == BannerMediaType.video) {
      final controller = _videoController;
      if (_isVideoInitialized && controller != null && !_hasError) {
        final size = controller.value.size;
        final videoW = size.width > 0 ? size.width : 16.0;
        final videoH = size.height > 0 ? size.height : 9.0;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: videoW,
              height: videoH,
              child: VideoPlayer(controller),
            ),
          ),
        );
      }

      // While video is loading or if playback failed, show poster (if present) or neutral state
      return _buildPosterOrPlaceholder(showSpinnerWhenNoPoster: !_hasError);
    }

    // Image slide
    final imageUrl = _resolvedMediaUrl;
    if (imageUrl == null || imageUrl.isEmpty || _hasError) {
      return _buildNeutralPlaceholder(showSpinner: false);
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => _buildNeutralPlaceholder(showSpinner: true),
      errorWidget: (_, __, ___) {
        if (!_retriedStorageRefresh && (_activeMedia?.hasStoragePath ?? false)) {
          _retriedStorageRefresh = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _prepareMedia(forceRefresh: true);
          });
          return _buildNeutralPlaceholder(showSpinner: true);
        }
        return _buildNeutralPlaceholder(showSpinner: false);
      },
    );
  }
}

/// Convenience helper binding [BannerRepository.resolveMediaUrl] to [BannerMediaView].
BannerMediaUrlResolver repositoryMediaUrlResolver(BannerRepository repository) {
  return (BannerMedia? media, {bool forceRefreshFromStorage = false}) {
    return repository.resolveMediaUrl(
      media,
      forceRefreshFromStorage: forceRefreshFromStorage,
    );
  };
}
