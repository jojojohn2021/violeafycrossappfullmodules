import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/app_providers.dart';
import 'product_story_dialog.dart';

class ProductCard extends ConsumerWidget {
  final ProductPerformance product;
  final bool restrictToPrimarySpecs;

  const ProductCard({
    super.key,
    required this.product,
    this.restrictToPrimarySpecs = false,
  });

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Widget _buildProductImage(ProductPerformance product) {
    final displayUrl = product.imageUrl ?? (product.images != null && product.images!.isNotEmpty ? product.images!.first : null);
    if (displayUrl != null && displayUrl.isNotEmpty && displayUrl.startsWith('http')) {
      if (_isMobilePlatform) {
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: CachedNetworkImage(
              imageUrl: displayUrl,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              placeholder: (context, url) => _buildPlaceholder(),
              errorWidget: (context, url, error) => _buildErrorWidget(),
            ),
          ),
        );
      }
      return CachedNetworkImage(
        imageUrl: displayUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildErrorWidget(),
      );
    }

    return _buildErrorWidget();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.secondaryBackground,
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: AppColors.secondaryBackground,
      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlist = ref.watch(wishlistProvider);
    final isWishlisted = wishlist.contains(product.id);

    final cart = ref.watch(cartProvider);
    final cartItemIndex = cart.indexWhere(
      (item) => !item.isPreorder && item.productId == product.id,
    );
    final currentCartQty = cartItemIndex >= 0 ? cart[cartItemIndex].quantity : 0;

    final price = product.offerPrice ?? product.onlinePrice;
    final mrp = product.mrp ?? product.shopPrice;
    final hasDiscount = mrp > price;
    final discountPercent = hasDiscount ? (((mrp - price) / mrp) * 100).round() : 0;

    return GestureDetector(
      onTap: () => context.push('/product-detail/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Stack (Image + Discount Badge + Wishlist Icon)
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildProductImage(product),
                  ),

                  // Discount Badge
                  if (discountPercent > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$discountPercent% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // Wishlist Toggle
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => ref.read(wishlistProvider.notifier).toggle(product.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          isWishlisted ? Icons.favorite : Icons.favorite_border,
                          color: isWishlisted ? AppColors.error : AppColors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Details Container
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (product.hasAyurvedicLanguageNames) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.packingSize.trim().isNotEmpty) ...[
                          Text(
                            product.packingSize,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: _CompactAyurvedicLanguageNames(product: product),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      product.packingSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 6),

                  // Price Row & Product Story button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            '₹${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (hasDiscount)
                            Text(
                              '₹${mrp.toStringAsFixed(0)}',
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                      // Short Product Story Button — shown only when backing field has a non-empty value
                      if (product.hasProductStory)
                        InkWell(
                          key: ValueKey('product_card_story_${product.id}'),
                          onTap: () async {
                            if (product.hasProductStory) {
                              ProductStoryDialog.show(
                                context,
                                title: product.name,
                                videoUrl: product.productStoryUrl!.trim(),
                              );
                              return;
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.primaryGreen, width: 0.8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle_fill, size: 10, color: AppColors.primaryGreen),
                                SizedBox(width: 3),
                                Text(
                                  'Product Story',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Unique specification highlights (immediately above rating)
                  if ((restrictToPrimarySpecs ? product.primaryUniqueSpecs : product.uniqueSpecs).isNotEmpty) ...[
                    UniqueSpecHighlights(
                      specs: restrictToPrimarySpecs ? product.primaryUniqueSpecs : product.uniqueSpecs,
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Star rating & review count (existing product rating fields)
                  if (product.rating != null && product.rating! > 0) ...[
                    ProductRatingRow(rating: product.rating!, reviewsCount: product.reviewsCount),
                    const SizedBox(height: 8),
                  ] else if ((restrictToPrimarySpecs ? product.primaryUniqueSpecs : product.uniqueSpecs).isNotEmpty)
                    const SizedBox(height: 4),

                  // Add to Cart / Pre-Order / Quantity Modifier Button
                  if (product.preorderactive)
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () =>
                            context.push('/product-detail/${product.id}'),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: const BorderSide(
                            color: AppColors.primaryGreen,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'PRE-ORDER',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    )
                  else if (currentCartQty == 0)
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(cartProvider.notifier).addToCart(product);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${product.name} added to cart'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'ADD',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          GestureDetector(
                            onTap: () => ref.read(cartProvider.notifier).updateQuantity(product.id, currentCartQty - 1),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(Icons.remove, color: Colors.white, size: 16),
                            ),
                          ),
                          Text(
                            '$currentCartQty',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => ref.read(cartProvider.notifier).updateQuantity(product.id, currentCartQty + 1),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(Icons.add, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactAyurvedicLanguageNames extends StatelessWidget {
  final ProductPerformance product;

  const _CompactAyurvedicLanguageNames({required this.product});

  @override
  Widget build(BuildContext context) {
    final rows = <(String?, String?)>[
      (product.sanskritName, product.malayalamName),
      (product.hindiName, product.kannadaName),
      (product.tamilName, product.teluguName),
    ].where((r) => r.$1 != null || r.$2 != null).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    const style = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.2,
    );

    return Column(
      key: ValueKey('product_card_ayurvedic_names_${product.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(
            children: [
              Expanded(
                child: Text(
                  row.$1 ?? '',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  row.$2 ?? '',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class UniqueSpecHighlights extends StatelessWidget {
  final List<String> specs;
  final double scale;

  const UniqueSpecHighlights({super.key, required this.specs, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4 * scale,
      runSpacing: 4 * scale,
      children: [
        for (final spec in specs)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
            decoration: BoxDecoration(
              color: AppColors.ratingStar,
              borderRadius: BorderRadius.circular(4 * scale),
              border: Border.all(color: AppColors.ratingStar, width: 0.8),
            ),
            child: Text(
              spec,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9 * scale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
      ],
    );
  }
}

class ProductRatingRow extends StatelessWidget {
  final double rating;
  final int? reviewsCount;
  final double scale;

  const ProductRatingRow({super.key, required this.rating, required this.reviewsCount, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final clamped = rating.clamp(0.0, 5.0);
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i == 5
                ? Icons.star_half // last star always shown as half
                : clamped >= i
                    ? Icons.star
                    : (clamped >= i - 0.5 ? Icons.star_half : Icons.star_border),
            color: AppColors.ratingStar,
            size: 12 * scale,
          ),
        SizedBox(width: 4 * scale),
        Flexible(
          child: Text(
            [
              // Rating number hidden for 5.0-rated products; review count still shown.
              if (rating < 5.0) rating.toStringAsFixed(1),
              if (reviewsCount != null && reviewsCount! > 0) '($reviewsCount)',
            ].join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10 * scale,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
