import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/firestore_image_widget.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/shimmer_loaders.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;

  Widget _buildBannerImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(color: AppColors.secondaryBackground);
    }

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: AppColors.secondaryBackground),
      );
    }

    return Container(color: AppColors.secondaryBackground);
  }

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

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final categoryModelsAsync = ref.watch(categoryModelsProvider);
    final bannersAsync = ref.watch(bannersProvider);
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
          ref.invalidate(bannersProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Promotional Banner Carousel loaded dynamically from backend
                  const SizedBox(height: 12),
                  bannersAsync.when(
                    data: (banners) {
                      if (banners.isEmpty) return const SizedBox();
                      return Column(
                        children: [
                          SizedBox(
                            height: 160,
                            child: PageView.builder(
                              controller: _bannerController,
                              onPageChanged: (index) => setState(() => _currentBannerIndex = index),
                              itemCount: banners.length,
                              itemBuilder: (context, index) {
                                final banner = banners[index];
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
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
                                    children: [
                                      Positioned.fill(
                                        child: _buildBannerImage(banner['image']),
                                      ),
                                      Positioned.fill(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                Colors.black.withValues(alpha: 0.75),
                                                Colors.black.withValues(alpha: 0.15),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 18,
                                        top: 24,
                                        bottom: 24,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              banner['title'] ?? 'Leafy Deal',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              banner['subtitle'] ?? 'Farm fresh offers',
                                              style: const TextStyle(
                                                color: AppColors.accentLime,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            if (banner['code'] != null && banner['code']!.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.25),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                                                ),
                                                child: Text(
                                                  'CODE: ${banner['code']}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              banners.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: _currentBannerIndex == i ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _currentBannerIndex == i ? AppColors.primaryGreen : AppColors.border,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const ShimmerBanner(),
                    error: (_, __) => const SizedBox(),
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
                      final allCategoryNames = categoryModels.map((m) => m.name).where((n) => n.isNotEmpty).toList();
                      final listNames = allCategoryNames.contains('All')
                          ? allCategoryNames
                          : ['All', ...allCategoryNames];

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
                                ref.read(selectedCategoryProvider.notifier).state = catName;
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

                  // 3. Referral & Wallet Promo Banners
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => context.push('/referrals'),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
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
                                        Text('Earn 5% on referrals', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => context.push('/wallet'),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.accentLime.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.accentLime.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.account_balance_wallet, color: AppColors.primaryGreen, size: 24),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Leafy Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                                        Text('Cashback & Payouts', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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

                  // 4. Production Product Catalog Grid from MongoDB
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

                  productsAsync.when(
                    data: (_) {
                      final filteredList = ref.watch(filteredProductsProvider);
                      if (filteredList.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: const Column(
                            children: [
                              Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
                              SizedBox(height: 12),
                              Text('No products found in this category.', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        );
                      }
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          int crossAxisCount = 2;
                          double childAspectRatio = 0.64;

                          if (width >= 900) {
                            crossAxisCount = 4;
                            childAspectRatio = 0.74;
                          } else if (width >= 600) {
                            crossAxisCount = 3;
                            childAspectRatio = 0.68;
                          }

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: childAspectRatio,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              return ProductCard(product: filteredList[index]);
                            },
                          );
                        },
                      );
                    },
                    loading: () => const ShimmerProductGrid(),
                    error: (err, __) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Failed to load products: $err', style: const TextStyle(color: AppColors.error)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
