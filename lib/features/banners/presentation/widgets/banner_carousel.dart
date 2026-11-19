import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/banner_models.dart';
import '../../domain/banner_route_validator.dart';
import 'banner_media_view.dart';

/// Reusable responsive mixed image/video banner carousel.
/// - Renders single-slide banners without unnecessary carousel controls.
/// - Uses desktop/mobile aspect ratios from [DynamicBanner.placementSpec].
/// - Coordinates image slide timers and video playback completion without
///   double timers or overlapping video controllers.
class BannerCarousel extends StatefulWidget {
  final DynamicBanner banner;
  final BannerMediaUrlResolver? mediaUrlResolver;
  final bool allowTopLevelPosterFallback;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final void Function(String validatedRoute)? onNavigate;

  const BannerCarousel({
    super.key,
    required this.banner,
    this.mediaUrlResolver,
    this.allowTopLevelPosterFallback = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 12),
    this.borderRadius = 16,
    this.onNavigate,
  });

  /// Responsive breakpoint matching desktop vs mobile media variants.
  static const double desktopBreakpoint = 768;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  Timer? _slideTimer;
  int _currentIndex = 0;

  List<BannerSlide> get _slides => widget.banner.resolvedSlides;
  bool get _isMultiSlide => _slides.length > 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scheduleCurrentSlideTimer();
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final slides = _slides;
    if (_currentIndex >= slides.length) {
      _currentIndex = 0;
      if (_pageController.hasClients && slides.isNotEmpty) {
        _pageController.jumpToPage(0);
      }
    }

    if (oldWidget.banner.id != widget.banner.id ||
        oldWidget.banner.updatedAt != widget.banner.updatedAt ||
        oldWidget.banner.autoplay != widget.banner.autoplay ||
        oldWidget.banner.loop != widget.banner.loop ||
        oldWidget.banner.resolvedSlides.length != slides.length) {
      _scheduleCurrentSlideTimer();
    }
  }

  void _cancelTimer() {
    _slideTimer?.cancel();
    _slideTimer = null;
  }

  /// Deterministic transition timing:
  /// - Always cancels any prior timer first (no double timers).
  /// - For images: waits `slide.slideDurationSec ?? placementSpec.slideDurationSec`.
  /// - For videos: coordinates with `onVideoCompleted`; sets a safety ceiling of
  ///   `max(configuredDuration, videoDuration) + 1s` so a slightly longer video
  ///   (e.g., 6.1s with slideDurationSec=6) is not cut off prematurely while
  ///   still advancing cleanly if playback stalls.
  void _scheduleCurrentSlideTimer() {
    _cancelTimer();

    final slides = _slides;
    if (!widget.banner.autoplay || slides.length <= 1) return;
    if (!widget.banner.loop && _currentIndex >= slides.length - 1) return;

    final slide = slides[_currentIndex];
    final configuredSec = slide.effectiveDurationSec(
      defaultSlideDurationSec: widget.banner.placementSpec.slideDurationSec,
    );

    Duration delay;
    if (slide.mediaType == BannerMediaType.video) {
      final desktopDur = slide.desktop?.durationSec ?? 0;
      final mobileDur = slide.mobile?.durationSec ?? 0;
      final maxVideoDur = math.max(desktopDur, mobileDur);
      final targetMs = math.max(configuredSec * 1000, (maxVideoDur * 1000).ceil()) + 1000;
      delay = Duration(milliseconds: targetMs);
    } else {
      delay = Duration(seconds: configuredSec);
    }

    _slideTimer = Timer(delay, _advanceSlide);
  }

  void _advanceSlide() {
    if (!mounted) return;
    final slides = _slides;
    if (slides.length <= 1) return;

    final isLast = _currentIndex >= slides.length - 1;
    if (isLast && !widget.banner.loop) {
      _cancelTimer();
      return;
    }

    final nextIndex = isLast ? 0 : _currentIndex + 1;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      setState(() => _currentIndex = nextIndex);
      _scheduleCurrentSlideTimer();
    }
  }

  void _handlePageChanged(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index);
    _scheduleCurrentSlideTimer();
  }

  void _handleVideoCompleted(int slideIndex) {
    if (!mounted || slideIndex != _currentIndex) return;
    if (!_isMultiSlide || !widget.banner.autoplay) return;
    _cancelTimer();
    _advanceSlide();
  }

  void _handleCtaTap(BannerCTA cta) {
    final validated = BannerRouteValidator.resolveSupportedRoute(cta.route);
    if (validated == null) {
      debugPrint('[BannerCarousel] Ignored unsupported CTA route: ${cta.route}');
      return;
    }
    if (widget.onNavigate != null) {
      widget.onNavigate!(validated);
      return;
    }
    context.push(validated);
  }

  double _computeHeight(double maxWidth, bool isDesktop) {
    final spec = widget.banner.placementSpec;
    final horizontalMargin = widget.margin.horizontal;
    final contentWidth = math.max(120.0, maxWidth - horizontalMargin);
    final ratio = isDesktop ? spec.desktopRatioValue : spec.mobileRatioValue;
    final rawHeight = contentWidth / ratio;

    // Placement-aware responsive height bounds to preserve existing page proportions
    switch (widget.banner.placement) {
      case BannerPlacement.strip:
        return rawHeight.clamp(96.0, isDesktop ? 180.0 : 150.0);
      case BannerPlacement.secondary:
      case BannerPlacement.spotlight:
      case BannerPlacement.footerPromo:
        return rawHeight.clamp(140.0, isDesktop ? 300.0 : 280.0);
      case BannerPlacement.hero:
      case null:
        return rawHeight.clamp(160.0, isDesktop ? 440.0 : 420.0);
    }
  }

  Widget _buildSlideContent(
    BannerSlide slide, {
    required int index,
    required bool isDesktop,
  }) {
    final title = slide.title;
    final subtitle = slide.subtitle;
    final cta = slide.cta;
    final validatedRoute =
        cta != null ? BannerRouteValidator.resolveSupportedRoute(cta.route) : null;
    final hasOverlayText = (title != null && title.isNotEmpty) ||
        (subtitle != null && subtitle.isNotEmpty) ||
        (cta != null && cta.isValid && validatedRoute != null);

    return GestureDetector(
      onTap: (cta != null && cta.isValid && validatedRoute != null)
          ? () => _handleCtaTap(cta)
          : null,
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BannerMediaView(
              key: ValueKey('${widget.banner.id}_${slide.id}_${isDesktop ? "d" : "m"}'),
              slide: slide,
              isDesktop: isDesktop,
              isActiveSlide: index == _currentIndex,
              autoplay: widget.banner.autoplay,
              loopVideo: !_isMultiSlide && widget.banner.loop,
              topLevelDesktopPoster: widget.banner.desktopPoster,
              topLevelMobilePoster: widget.banner.mobilePoster,
              allowTopLevelPosterFallback: widget.allowTopLevelPosterFallback,
              mediaUrlResolver: widget.mediaUrlResolver,
              onVideoCompleted: () => _handleVideoCompleted(index),
            ),
            if (hasOverlayText) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.accentLime,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (cta != null && cta.isValid && validatedRoute != null) ...[
                      const SizedBox(height: 10),
                      ElevatedButton(
                        key: ValueKey('banner_cta_${slide.id}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _handleCtaTap(cta),
                        child: Text(
                          cta.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelTimer();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    if (slides.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isDesktop = width >= BannerCarousel.desktopBreakpoint;
        final height = _computeHeight(width, isDesktop);

        // Single-slide banner: render cleanly without unnecessary carousel controls
        if (!_isMultiSlide) {
          return SizedBox(
            width: double.infinity,
            height: height,
            child: _buildSlideContent(
              slides.first,
              index: 0,
              isDesktop: isDesktop,
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: height,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _handlePageChanged,
                itemCount: slides.length,
                itemBuilder: (context, index) => _buildSlideContent(
                  slides[index],
                  index: index,
                  isDesktop: isDesktop,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              key: const ValueKey('banner_slide_indicators'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                slides.length,
                (i) => GestureDetector(
                  onTap: () {
                    if (_pageController.hasClients) {
                      _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentIndex == i ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentIndex == i
                          ? AppColors.primaryGreen
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
