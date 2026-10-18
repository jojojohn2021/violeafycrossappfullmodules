import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../data/review_models.dart';

/// Thumbnail tile for a customer photo/video. Videos show a play indicator; failed loads degrade gracefully.
class ReviewMediaThumb extends StatelessWidget {
  final ReviewMedia media;
  final double size;
  final VoidCallback onTap;
  final String? overlayLabel;

  const ReviewMediaThumb({super.key, required this.media, required this.onTap, this.size = 96, this.overlayLabel});

  @override
  Widget build(BuildContext context) {
    final imageUrl = media.isVideo ? media.thumbnailUrl : media.url;
    return Semantics(
      button: true,
      label: media.isVideo ? 'Customer video' : 'Customer photo',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: media.isVideo ? const Color(0xFF1F2A20) : AppColors.secondaryBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * 2).round(),
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) => const ColoredBox(color: AppColors.shimmerBase),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                )
              else if (!media.isVideo)
                const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
              if (media.isVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              if (media.isVideo)
                const Positioned(
                  left: 6,
                  bottom: 4,
                  child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 16),
                ),
              if (overlayLabel != null)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Text(overlayLabel!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen viewer with swipe/arrow navigation across photos and videos.
class ReviewMediaViewer extends StatefulWidget {
  final List<ReviewMedia> items;
  final int initialIndex;

  const ReviewMediaViewer({super.key, required this.items, required this.initialIndex});

  static Future<void> show(BuildContext context, List<ReviewMedia> items, int index) {
    return showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => ReviewMediaViewer(items: items, initialIndex: index),
    );
  }

  @override
  State<ReviewMediaViewer> createState() => _ReviewMediaViewerState();
}

class _ReviewMediaViewerState extends State<ReviewMediaViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.items.length - 1);
    _page.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.items[_index];
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final m = widget.items[i];
              if (m.url == null) {
                return const Center(child: Text('This media is unavailable', style: TextStyle(color: Colors.white70)));
              }
              return m.isVideo
                  ? _VideoPane(key: ValueKey(m.mediaId), url: m.url!, active: i == _index)
                  : InteractiveViewer(
                      maxScale: 4,
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: m.url!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white54),
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
                        ),
                      ),
                    );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_index + 1} / ${widget.items.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        if ((current.customerDisplayName ?? '').isNotEmpty)
                          Text(current.customerDisplayName!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          if (widget.items.length > 1) ...[
            if (_index > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 40),
                  onPressed: () => _go(-1),
                ),
              ),
            if (_index < widget.items.length - 1)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 40),
                  onPressed: () => _go(1),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VideoPane extends StatefulWidget {
  final String url;
  final bool active;
  const _VideoPane({super.key, required this.url, required this.active});

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.active) _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant _VideoPane old) {
    super.didUpdateWidget(old);
    if (!widget.active && _c.value.isPlaying) _c.pause();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Text('Video could not be played', style: TextStyle(color: Colors.white70)));
    }
    if (!_c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    return GestureDetector(
      onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
          if (!_c.value.isPlaying)
            const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 72),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: VideoProgressIndicator(_c, allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: AppColors.primaryGreenLight)),
          ),
        ],
      ),
    );
  }
}
