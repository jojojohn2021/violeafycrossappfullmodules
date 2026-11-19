import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/banner_models.dart';
import '../banner_providers.dart';
import 'banner_carousel.dart';
import 'banner_media_view.dart';

/// Drop-in Riverpod widget that renders active dynamic banners from the
/// Firestore `banners` collection for a specific [pageType], [placement],
/// and optional [pageId]. Collapses to [SizedBox.shrink] when empty/error
/// unless [emptyBuilder] is supplied.
class DynamicBannerSlot extends ConsumerWidget {
  final BannerPageType pageType;
  final BannerPlacement placement;
  final String? pageId;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool allowTopLevelPosterFallback;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? emptyBuilder;

  const DynamicBannerSlot({
    super.key,
    this.pageType = BannerPageType.defaultValue,
    this.placement = BannerPlacement.defaultValue,
    this.pageId,
    this.margin = const EdgeInsets.symmetric(horizontal: 12),
    this.padding = EdgeInsets.zero,
    this.borderRadius = 16,
    this.allowTopLevelPosterFallback = false,
    this.loadingBuilder,
    this.emptyBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = BannerQuery(
      pageType: pageType,
      placement: placement,
      pageId: pageId,
    );
    final bannersAsync = ref.watch(dynamicBannersProvider(query));
    final repository = ref.watch(bannerRepositoryProvider);

    return bannersAsync.when(
      loading: () =>
          loadingBuilder != null ? loadingBuilder!(context) : const SizedBox.shrink(),
      error: (_, __) =>
          emptyBuilder != null ? emptyBuilder!(context) : const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) {
          return emptyBuilder != null
              ? emptyBuilder!(context)
              : const SizedBox.shrink();
        }

        final resolver =
            repository != null ? repositoryMediaUrlResolver(repository) : null;
        return Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < banners.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                BannerCarousel(
                  key: ValueKey('dynamic_banner_${banners[i].id}'),
                  banner: banners[i],
                  mediaUrlResolver: resolver,
                  allowTopLevelPosterFallback: allowTopLevelPosterFallback,
                  margin: margin,
                  borderRadius: borderRadius,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
