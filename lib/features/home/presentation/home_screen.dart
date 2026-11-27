import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/firestore_image_widget.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/leafy_web_footer.dart';
import '../../banners/banner_module.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Color _getColorForCategory(String category) {
    final normalized = category.toLowerCase();

    if (normalized.contains('fruit')) return const Color(0xFFFFF3E0);
    if (normalized.contains('vegetable') || normalized.contains('veg')) return const Color(0xFFE8F5E9);
    if (normalized.contains('dairy') || normalized.contains('milk')) return const Color(0xFFE3F2FD);
    if (normalized.contains('grain') || normalized.contains('rice') || normalized.contains('cereal')) return const Color(0xFFF3E5F5);
    if (normalized.contains('beverage') || normalized.contains('drink')) return const Color(0xFFE0F7FA);
    if (normalized.contains('snack') || normalized.contains('biscuit') || normalized.contains('sweet')) return const Color(0xFFFFE0B2);

    return const Color(0xFFE8F5E9);
  }

  IconData _getIconForCategory(String category) {
    final normalized = category.toLowerCase();

    if (normalized.contains('fruit')) return Icons.apple;
    if (normalized.contains('vegetable') || normalized.contains('veg')) return Icons.eco;
    if (normalized.contains('dairy') || normalized.contains('milk')) return Icons.local_drink;
    if (normalized.contains('grain') || normalized.contains('rice') || normalized.contains('cereal')) return Icons.grain;
    if (normalized.contains('beverage') || normalized.contains('drink')) return Icons.local_cafe;
    if (normalized.contains('snack') || normalized.contains('biscuit') || normalized.contains('sweet')) return Icons.cookie;

    return Icons.category;
  }

  /// Orders products by their category's `homepagesortorder` (product_categories).
  /// Products in multiple categories use the lowest order; unmatched ones go last.
  /// Stable: original order is kept within the same sort value.
  List<ProductPerformance> _sortByCategoryHomepageOrder(
    List<ProductPerformance> products,
    List<ProductCategory> categoryModels,
  ) {
    final orderByKey = <String, int>{};
    for (final c in categoryModels) {
      final o = c.homepageSortOrder;
      if (o == null) continue;
      orderByKey[c.name.trim().toLowerCase()] = o;
      orderByKey[c.id.trim().toLowerCase()] = o;
    }
    if (orderByKey.isEmpty) return products;

    int keyFor(ProductPerformance p) {
      final cats = <String>[
        ...?p.categories,
        if (p.categories == null || p.categories!.isEmpty) ...(p.category ?? '').split(','),
      ];
      var best = 1 << 30;
      for (final c in cats) {
        final o = orderByKey[c.trim().toLowerCase()];
        if (o != null && o < best) best = o;
      }
      return best;
    }

    final indexed = products.asMap().entries.toList()
      ..sort((a, b) {
        final cmp = keyFor(a.value).compareTo(keyFor(b.value));
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final categoryModelsAsync = ref.watch(categoryModelsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async {
          ref.invalidate(productsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(categoryModelsProvider);
          ref.invalidate(brandModelsProvider);
          ref.invalidate(brandOwnerModelsProvider);
          ref.invalidate(dynamicBannersProvider);
        },
        child: LayoutBuilder(
          builder: (context, viewportConstraints) {
            final viewportWidth = viewportConstraints.maxWidth;
            final contentWidth = viewportWidth > 1400 ? 1400.0 : viewportWidth;
            final outerHorizontalPadding =
                viewportWidth > 1400 ? (viewportWidth - 1400.0) / 2.0 : 0.0;

            final isMobilePlatform = !kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS);
            int crossAxisCount = 2;
            double childAspectRatio = 0.64;

            if (contentWidth >= 900) {
              crossAxisCount = 4;
              childAspectRatio = 0.74;
            } else if (contentWidth >= 600) {
              crossAxisCount = 3;
              childAspectRatio = 0.68;
            }

            double? mainAxisExtent;
            if (isMobilePlatform) {
              final cardWidth =
                  (contentWidth - 24 - ((crossAxisCount - 1) * 12)) / crossAxisCount;
              final targetImageHeight = cardWidth.clamp(180.0, 200.0);
              mainAxisExtent = targetImageHeight + 178.0;
            }

            final filteredList = productsAsync.maybeWhen(
              data: (_) => _sortByCategoryHomepageOrder(
                ref.watch(filteredProductsProvider),
                categoryModelsAsync.value ?? const [],
              ),
              orElse: () => const <ProductPerformance>[],
            );

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Dynamic Mixed Image/Video Hero Banner Carousel (Firestore `banners`)
                        const SizedBox(height: 12),
                        DynamicBannerSlot(
                          pageType: BannerPageType.home,
                          placement: BannerPlacement.hero,
                          allowTopLevelPosterFallback: true,
                          loadingBuilder: (_) => const ShimmerBanner(),
                        ),

                        // 2. Compact Meesho-style Category Carousel (Positioned directly below Banners / Search Bar)
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Categories',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              GestureDetector(
                                onTap: () => context.go('/categories'),
                                child: const Text(
                                  'See All',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryGreen),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        categoryModelsAsync.when(
                          data: (categoryModels) {
                            final listNames = categoryModels
                                .map((m) => m.name.trim())
                                .where((n) => n.isNotEmpty && n.toLowerCase() != 'all')
                                .toList();

                            return SizedBox(
                              height: 92,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: listNames.length,
                                itemBuilder: (context, index) {
                                  final catName = listNames[index];
                                  final isSelected = selectedCategory == catName;
                                  final matchingModel = categoryModels.firstWhere(
                                    (m) => m.name.toLowerCase() == catName.toLowerCase(),
                                    orElse: () => ProductCategory(id: catName, name: catName),
                                  );

                                  return GestureDetector(
                                    onTap: () {
                                      ref.read(selectedCategoryProvider.notifier).state =
                                          isSelected ? 'All' : catName;
                                    },
                                    child: Container(
                                      width: 76,
                                      margin: const EdgeInsets.only(right: 8),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 54,
                                            height: 54,
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSelected
                                                  ? AppColors.primaryGreen.withValues(alpha: 0.15)
                                                  : AppColors.secondaryBackground,
                                              border: Border.all(
                                                color: isSelected ? AppColors.primaryGreen : AppColors.border.withValues(alpha: 0.6),
                                                width: isSelected ? 2.5 : 1,
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: AppColors.primaryGreen.withValues(alpha: 0.2),
                                                        blurRadius: 6,
                                                        offset: const Offset(0, 2),
                                                      )
                                                    ]
                                                  : null,
                                            ),
                                            child: ClipOval(
                                              child: catName == 'All'
                                                  ? Container(
                                                      color: isSelected ? AppColors.primaryGreen : AppColors.secondaryBackground,
                                                      child: Icon(
                                                        Icons.grid_view_rounded,
                                                        color: isSelected ? Colors.white : AppColors.primaryGreen,
                                                        size: 24,
                                                      ),
                                                    )
                                                  : FirestoreImageWidget(
                                                      collection: 'product_categories',
                                                      docIdOrRef: matchingModel.imageId ?? matchingModel.id,
                                                      directImageUrl: matchingModel.imageUrl,
                                                      cacheWidth: 120,
                                                      fit: BoxFit.cover,
                                                      fallbackWidget: Container(
                                                        color: _getColorForCategory(catName),
                                                        child: Icon(
                                                          _getIconForCategory(catName),
                                                          color: AppColors.primaryGreen,
                                                          size: 24,
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            catName,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? AppColors.primaryGreen : AppColors.textPrimary,
                                              height: 1.1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          loading: () => SizedBox(
                            height: 92,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: 6,
                              itemBuilder: (context, index) => Container(
                                width: 76,
                                margin: const EdgeInsets.only(right: 8),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 54,
                                      height: 54,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.secondaryBackground,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      width: 48,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: AppColors.secondaryBackground,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          error: (_, __) => const SizedBox(),
                        ),

                        // Optional Home Secondary Banner Slot (collapses when none active)
                        const DynamicBannerSlot(
                          pageType: BannerPageType.home,
                          placement: BannerPlacement.secondary,
                          padding: EdgeInsets.only(top: 14),
                        ),

                        // 3. Referral & Wallet Promo Banners
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    key: const ValueKey('home_preorder_booking_label'),
                                    onTap: () => context.push('/preorders'),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      alignment: Alignment.centerLeft,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryGreen.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
                                      ),
                                      child: const Text(
                                        'Pre-order booking',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => context.push('/referrals'),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentLime.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.accentLime.withValues(alpha: 0.4)),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.share, color: AppColors.primaryGreen, size: 24),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Refer & Earn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                                                Text('Earn on referrals', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Optional Home Strip Banner Slot (collapses when none active)
                        const DynamicBannerSlot(
                          pageType: BannerPageType.home,
                          placement: BannerPlacement.strip,
                          padding: EdgeInsets.only(top: 14),
                        ),

                        // 4. Production Product Catalog Grid Header
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                selectedCategory == 'All' ? 'Featured Products' : selectedCategory,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              Text(
                                '${ref.watch(filteredProductsProvider).length} Items',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // Lazy-virtualized Product Catalog SliverGrid
                productsAsync.when(
                  data: (_) {
                    if (filteredList.isEmpty) {
                      return SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            alignment: Alignment.center,
                            child: const Column(
                              children: [
                                Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
                                SizedBox(height: 12),
                                Text('No products found in this category.', style: TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        outerHorizontalPadding + 12,
                        6,
                        outerHorizontalPadding + 12,
                        6,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: childAspectRatio,
                          mainAxisExtent: mainAxisExtent,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ProductCard(
                            product: filteredList[index],
                            restrictToPrimarySpecs: true,
                          ),
                          childCount: filteredList.length,
                        ),
                      ),
                    );
                  },
                  loading: () => SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding),
                    sliver: const SliverToBoxAdapter(child: ShimmerProductGrid()),
                  ),
                  error: (err, __) => SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding),
                    sliver: SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('Failed to load products: $err', style: const TextStyle(color: AppColors.error)),
                      ),
                    ),
                  ),
                ),

                // Footer banners & Web Footer
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: outerHorizontalPadding),
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DynamicBannerSlot(
                          pageType: BannerPageType.home,
                          placement: BannerPlacement.spotlight,
                          padding: EdgeInsets.only(top: 16),
                        ),
                        DynamicBannerSlot(
                          pageType: BannerPageType.home,
                          placement: BannerPlacement.footerPromo,
                          padding: EdgeInsets.only(top: 16),
                        ),
                        SizedBox(height: 24),
                        if (kIsWeb) LeafyWebFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
