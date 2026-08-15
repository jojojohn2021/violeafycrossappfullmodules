import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  Widget _buildProductImage(ProductPerformance product) {
    final displayUrl = product.imageUrl ?? (product.images != null && product.images!.isNotEmpty ? product.images!.first : null);
    if (displayUrl != null && displayUrl.isNotEmpty && displayUrl.startsWith('http')) {
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
      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted, size: 48),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final wishlist = ref.watch(wishlistProvider);
    final isWishlisted = wishlist.contains(productId);

    final cart = ref.watch(cartProvider);
    final cartItemIndex = cart.indexWhere((item) => item.productId == productId);
    final currentCartQty = cartItemIndex >= 0 ? cart[cartItemIndex].quantity : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Product Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              isWishlisted ? Icons.favorite : Icons.favorite_border,
              color: isWishlisted ? AppColors.error : AppColors.textPrimary,
            ),
            onPressed: () => ref.read(wishlistProvider.notifier).toggle(productId),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: productsAsync.when(
        data: (products) {
          final ProductPerformance product;
          try {
            product = products.firstWhere((p) => p.id == productId);
          } catch (_) {
            return const Center(child: Text('Product not found'));
          }

          final price = product.offerPrice ?? product.onlinePrice;
          final mrp = product.mrp ?? product.shopPrice;
          final hasDiscount = mrp > price;
          final discountPercent = hasDiscount ? (((mrp - price) / mrp) * 100).round() : 0;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Large Image Hero
                      AspectRatio(
                        aspectRatio: 1.2,
                        child: Hero(
                          tag: 'product-${product.id}',
                          child: _buildProductImage(product),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category & Rating Pill
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    product.category ?? 'Fresh Organic',
                                    style: const TextStyle(
                                      color: AppColors.primaryGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (product.rating != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: AppColors.ratingStar, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${product.rating} (${product.reviewsCount ?? 120} reviews)',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Product Name
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Packing: ${product.packingSize}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),

                            // Price & Discount Row
                            Row(
                              children: [
                                Text(
                                  '₹${price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (hasDiscount) ...[
                                  Text(
                                    '₹${mrp.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      fontSize: 16,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$discountPercent% OFF',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const Divider(height: 32),

                            // Description & Specifications
                            const Text(
                              'Product Description',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              product.description ??
                                  'Direct from certified organic partner farms. Carefully cleaned, quality inspected, and packaged for maximum freshness and long shelf life.',
                              style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 16),

                            // Highlights
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.secondaryBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.local_shipping_outlined, color: AppColors.primaryGreen, size: 20),
                                      SizedBox(width: 10),
                                      Text('Same Day Express Delivery', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.verified_outlined, color: AppColors.primaryGreen, size: 20),
                                      SizedBox(width: 10),
                                      Text('100% Quality Guaranteed or Instant Refund', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Sticky Add to Cart Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2)),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      if (currentCartQty > 0)
                        Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.secondaryBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 18),
                                onPressed: () => ref.read(cartProvider.notifier).updateQuantity(product.id, currentCartQty - 1),
                              ),
                              Text('$currentCartQty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              IconButton(
                                icon: const Icon(Icons.add, size: 18),
                                onPressed: () => ref.read(cartProvider.notifier).updateQuantity(product.id, currentCartQty + 1),
                              ),
                            ],
                          ),
                        ),
                      if (currentCartQty > 0) const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () {
                              if (currentCartQty == 0) {
                                ref.read(cartProvider.notifier).addToCart(product);
                              }
                              context.push('/cart');
                            },
                            child: Text(
                              currentCartQty == 0 ? 'ADD TO CART' : 'GO TO CART',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
