import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/product_story_dialog.dart';
import '../../preorder/presentation/widgets/preorder_widgets.dart';
import '../../reviews/presentation/customer_reviews_section.dart';
import '../../banners/banner_module.dart';

/// Resolves a product by its Firestore document ID.
/// Uses the already-loaded product list (existing cache) first and only falls back
/// to the existing repository lookup when the product isn't in that list.
final _productDetailProvider =
    FutureProvider.autoDispose.family<ProductPerformance?, String>((ref, id) async {
  final products = await ref.watch(productsProvider.future);
  for (final p in products) {
    if (p.id == id) return p;
  }
  return ref.read(shoppingRepositoryProvider).getProductById(id);
});

const double _wideBreakpoint = 900;

String? _clean(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty || t.toLowerCase() == 'null') ? null : t;
}

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(_productDetailProvider(productId));
    final isWishlisted = ref.watch(wishlistProvider).contains(productId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Product Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            key: const ValueKey('product_detail_home_btn'),
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, color: AppColors.primaryGreen, size: 20),
            label: const Text(
              'Home',
              style: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              isWishlisted ? Icons.favorite : Icons.favorite_border,
              color: isWishlisted ? AppColors.error : AppColors.textPrimary,
            ),
            onPressed: () => ref.read(wishlistProvider.notifier).toggle(productId),
          ),
        ],
      ),
      body: productAsync.when(
        data: (product) {
          if (product == null) return const _NotFound();
          return _ProductDetailBody(key: ValueKey(product.id), product: product);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load product: $err', style: const TextStyle(color: AppColors.error)),
          ),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('Product not found', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(onPressed: () => context.go('/'), child: const Text('Back to Home')),
        ],
      ),
    );
  }
}

class _ProductDetailBody extends ConsumerWidget {
  final ProductPerformance product;

  const _ProductDetailBody({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= _wideBreakpoint;

      final gallery = _ProductGallery(product: product);
      final info = _ProductInfo(product: product, showInlinePurchase: isWide);
      final details = _ProductDetailsSections(product: product);
      final related = _RelatedProducts(product: product);
      final reviews = CustomerReviewsSection(productId: product.id, productName: product.name);
      final productBanner = DynamicBannerSlot(
        pageType: BannerPageType.product,
        placement: BannerPlacement.strip,
        pageId: product.id,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.only(bottom: 16),
      );

      final content = isWide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Breadcrumb(product: product),
                const SizedBox(height: 16),
                productBanner,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: gallery),
                    const SizedBox(width: 32),
                    Expanded(flex: 10, child: info),
                  ],
                ),
                const SizedBox(height: 28),
                details,
                reviews,
                related,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                productBanner,
                gallery,
                const SizedBox(height: 16),
                info,
                const SizedBox(height: 8),
                details,
                reviews,
                related,
              ],
            );

      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: isWide ? 20 : 12),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
          if (!isWide && !product.preorderactive) _BottomPurchaseBar(product: product),
        ],
      );
    });
  }
}

// ─────────────────────────────── Breadcrumb ───────────────────────────────

class _Breadcrumb extends ConsumerWidget {
  final ProductPerformance product;

  const _Breadcrumb({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = _clean(product.categories?.isNotEmpty == true ? product.categories!.first : product.category);
    const muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const link = TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.w600);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(onTap: () => context.go('/'), child: const Text('Home', style: link)),
        if (category != null) ...[
          const Text('  /  ', style: muted),
          InkWell(
            onTap: () {
              ref.read(selectedCategoryProvider.notifier).state = category;
              context.go('/');
            },
            child: Text(category, style: link),
          ),
        ],
        const Text('  /  ', style: muted),
        Text(product.name, style: muted, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ─────────────────────────────── Gallery ───────────────────────────────

class _ProductGallery extends ConsumerStatefulWidget {
  final ProductPerformance product;

  const _ProductGallery({required this.product});

  @override
  ConsumerState<_ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends ConsumerState<_ProductGallery> {
  int _selected = 0;

  List<String> get _images {
    final p = widget.product;
    final urls = <String>[
      if (p.imageUrl != null) p.imageUrl!,
      ...?p.images,
    ];
    final seen = <String>{};
    return urls.where((u) => u.startsWith('http') && seen.add(u)).toList();
  }

  Future<void> _openStory() async {
    final p = widget.product;
    if (_clean(p.productStoryUrl) != null) {
      ProductStoryDialog.show(context, title: p.name, videoUrl: p.productStoryUrl!);
      return;
    }
    // Existing server API (with Firestore fallback) used by product cards.
    final story = await ref.read(shoppingRepositoryProvider).getProductStoryVideo(p.id);
    if (!mounted) return;
    final url = story?['videoUrl']?.toString();
    if (url != null && url.isNotEmpty) {
      ProductStoryDialog.show(context, title: story?['title']?.toString() ?? p.name, videoUrl: url);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('No product story video available for this item'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ));
    }
  }

  void _openZoom(List<String> images, int index) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ZoomViewer(images: images, initialIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final selected = images.isEmpty ? 0 : _selected.clamp(0, images.length - 1);

    final mainImage = Container(
      decoration: BoxDecoration(
        color: AppColors.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: images.isEmpty
                  ? const Center(child: Icon(Icons.image_not_supported_outlined, size: 56, color: AppColors.textMuted))
                  : GestureDetector(
                      onTap: () => _openZoom(images, selected),
                      child: Hero(
                        tag: 'product-${widget.product.id}',
                        child: CachedNetworkImage(
                          imageUrl: images[selected],
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                          ),
                          errorWidget: (_, __, ___) =>
                              const Center(child: Icon(Icons.image_not_supported_outlined, size: 56, color: AppColors.textMuted)),
                        ),
                      ),
                    ),
            ),
            if (images.isNotEmpty)
              Positioned(
                right: 10,
                top: 10,
                child: _RoundIcon(icon: Icons.zoom_out_map, onTap: () => _openZoom(images, selected)),
              ),
            if (widget.product.hasProductStory)
              Positioned(
                left: 10,
                bottom: 10,
                child: Material(
                  key: ValueKey('product_detail_story_${widget.product.id}'),
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _openStory,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill, size: 18, color: AppColors.primaryGreen),
                          SizedBox(width: 6),
                          Text('Product Story',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mainImage,
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final isSel = i == selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 68,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel ? AppColors.primaryGreen : AppColors.border,
                        width: isSel ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 18, color: AppColors.textPrimary)),
      ),
    );
  }
}

class _ZoomViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ZoomViewer({required this.images, required this.initialIndex});

  @override
  State<_ZoomViewer> createState() => _ZoomViewerState();
}

class _ZoomViewerState extends State<_ZoomViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 56),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Info ───────────────────────────────

/// Pricing exactly as used by ProductCard and the cart (offerPrice ?? onlinePrice, mrp ?? shopPrice).
class _Pricing {
  final double price;
  final double mrp;
  final bool hasDiscount;
  final int discountPercent;

  factory _Pricing.of(ProductPerformance p) {
    final price = p.offerPrice ?? p.onlinePrice;
    final mrp = p.mrp ?? p.shopPrice;
    final hasDiscount = mrp > price && price > 0;
    return _Pricing._(price, mrp, hasDiscount, hasDiscount ? (((mrp - price) / mrp) * 100).round() : 0);
  }

  const _Pricing._(this.price, this.mrp, this.hasDiscount, this.discountPercent);
}

class _ProductInfo extends StatelessWidget {
  final ProductPerformance product;
  final bool showInlinePurchase;

  const _ProductInfo({required this.product, required this.showInlinePurchase});

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(product);
    final packSize = _clean(product.packingSize);
    final brand = _clean(product.brand);
    final stockText = _clean(product.stockAvailability);
    final specs = product.uniqueSpecs;
    final hasRating = product.rating != null && product.rating! > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (brand != null) ...[
          Text(brand, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryGreen)),
          const SizedBox(height: 4),
        ],
        // 1. Name
        Text(
          product.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.25),
        ),
        // 2. Pack size (+ Ayurvedic language-specific names when ayurvedicproduct == true)
        if (product.hasAyurvedicLanguageNames) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (packSize != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 16),
                  child: Text(
                    packSize,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ),
              ],
              Expanded(
                child: _AyurvedicLanguageNamesGrid(product: product),
              ),
            ],
          ),
        ] else if (packSize != null) ...[
          const SizedBox(height: 6),
          Text(packSize, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
        // 3. Unique specs
        if (specs.isNotEmpty) ...[
          const SizedBox(height: 12),
          UniqueSpecHighlights(specs: specs, scale: 1.4),
        ],
        // 4. Rating
        if (hasRating) ...[
          const SizedBox(height: 10),
          ProductRatingRow(rating: product.rating!, reviewsCount: product.reviewsCount, scale: 1.4),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 16),
        // 5–7. Price / MRP / discount
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            Text('₹${pricing.price.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            if (pricing.hasDiscount) ...[
              Text('MRP ₹${pricing.mrp.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textMuted, decoration: TextDecoration.lineThrough)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(6)),
                child: Text('${pricing.discountPercent}% OFF',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        const Text('(Inclusive of all taxes)', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        if (pricing.hasDiscount) ...[
          const SizedBox(height: 6),
          Text('You save ₹${(pricing.mrp - pricing.price).toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
        ],
        // 9. Stock (existing field; always shown before Pre-Order Booking Details when preorderactive is true)
        if (stockText != null || product.preorderactive) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(stockText ?? 'In Stock',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ],
        // 10. Conditional Purchase / Pre-Order Booking Controls
        if (product.preorderactive) ...[
          const SizedBox(height: 16),
          PreorderBookingDetailsSection(product: product),
        ] else if (showInlinePurchase) ...[
          const SizedBox(height: 20),
          SizedBox(width: 280, child: _CartControl(product: product, height: 48)),
        ],
        // 11. Product Highlights directly below Add to Cart (within gallery height on desktop, natural reflow on mobile)
        if (product.productHighlights.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ProductHighlightsCard(
            highlights: product.productHighlights,
            compactForDesktop: showInlinePurchase,
          ),
        ],
      ],
    );
  }
}

class _AyurvedicLanguageNamesGrid extends StatelessWidget {
  final ProductPerformance product;

  const _AyurvedicLanguageNamesGrid({required this.product});

  @override
  Widget build(BuildContext context) {
    final rows = <(String?, String?)>[
      (product.sanskritName, product.malayalamName),
      (product.hindiName, product.kannadaName),
      (product.tamilName, product.teluguName),
    ].where((r) => r.$1 != null || r.$2 != null).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    const style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.35,
    );

    return Column(
      key: ValueKey('ayurvedic_names_${product.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rows[i].$1 ?? '',
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rows[i].$2 ?? '',
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProductHighlightsCard extends StatelessWidget {
  final List<String> highlights;
  final bool compactForDesktop;

  const _ProductHighlightsCard({
    required this.highlights,
    required this.compactForDesktop,
  });

  @override
  Widget build(BuildContext context) {
    // Reference requests 4–6 bullets; never fabricate extras if fewer exist, cap at 6 on desktop to stay aligned with gallery bottom.
    final visibleItems = compactForDesktop && highlights.length > 6
        ? highlights.take(6).toList()
        : highlights;

    final cardContent = Container(
      key: const ValueKey('product_highlights_card'),
      width: double.infinity,
      padding: EdgeInsets.all(compactForDesktop ? 14 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: AppColors.primaryGreen),
              SizedBox(width: 6),
              Text(
                'PRODUCT HIGHLIGHTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < visibleItems.length; i++) ...[
            if (i > 0) SizedBox(height: compactForDesktop ? 6 : 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    visibleItems[i],
                    maxLines: compactForDesktop ? 2 : null,
                    overflow: compactForDesktop ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      fontSize: compactForDesktop ? 12.5 : 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    // On desktop, bound vertical extent so it stays within the bottom of the product image thumbnail strip.
    if (compactForDesktop) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 270),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

// ─────────────────────────────── Cart controls ───────────────────────────────

class _CartControl extends ConsumerWidget {
  final ProductPerformance product;
  final double height;

  const _CartControl({required this.product, this.height = 46});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final idx = cart.indexWhere((item) => item.productId == product.id);
    final qty = idx >= 0 ? cart[idx].quantity : 0;
    final notifier = ref.read(cartProvider.notifier);

    if (qty == 0) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            notifier.addToCart(product);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('${product.name} added to cart'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(label: 'VIEW CART', onPressed: () => context.push('/cart')),
              ));
          },
          child: const Text('ADD TO CART', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(color: AppColors.primaryGreen, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Decrease quantity',
                  icon: const Icon(Icons.remove, color: Colors.white, size: 20),
                  onPressed: () => notifier.updateQuantity(product.id, qty - 1),
                ),
                Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  tooltip: 'Increase quantity',
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  onPressed: () => notifier.updateQuantity(product.id, qty + 1),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: height,
          width: height,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => context.push('/cart'),
            child: const Tooltip(
              message: 'View cart',
              child: Icon(Icons.shopping_cart_outlined, color: AppColors.primaryGreen, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomPurchaseBar extends StatelessWidget {
  final ProductPerformance product;

  const _BottomPurchaseBar({required this.product});

  @override
  Widget build(BuildContext context) {
    final pricing = _Pricing.of(product);
    final packSize = _clean(product.packingSize);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Flexible(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (packSize != null)
                  Text(packSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text('₹${pricing.price.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    if (pricing.hasDiscount)
                      Text('₹${pricing.mrp.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted, decoration: TextDecoration.lineThrough)),
                  ],
                ),
                const Text('Inclusive of all taxes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _CartControl(product: product)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Details sections ───────────────────────────────

class _ProductDetailsSections extends StatefulWidget {
  final ProductPerformance product;

  const _ProductDetailsSections({required this.product});

  @override
  State<_ProductDetailsSections> createState() => _ProductDetailsSectionsState();
}

class _ProductDetailsSectionsState extends State<_ProductDetailsSections> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final category = _clean(product.categories?.isNotEmpty == true ? product.categories!.join(', ') : product.category);
    // Product Details metadata labels in exact reference order: Brand, Category, Pack Size, Unit, Marketed By
    final facts = <MapEntry<String, String>>[
      if (_clean(product.brand) != null) MapEntry('Brand', _clean(product.brand)!),
      if (category != null) MapEntry('Category', category),
      if (_clean(product.packingSize) != null) MapEntry('Pack Size', _clean(product.packingSize)!),
      if (_clean(product.unit) != null) MapEntry('Unit', _clean(product.unit)!),
      if (_clean(product.brandOwner) != null) MapEntry('Marketed By', _clean(product.brandOwner)!),
    ];

    final detailSubSections = <Widget>[
      if (facts.isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: _FactsTable(facts: facts),
        ),
      if (product.keyFeatures.isNotEmpty)
        _Section(title: 'KEY FEATURES', initiallyExpanded: true, child: _BulletList(items: product.keyFeatures)),
      if (product.dietaryAttributes.isNotEmpty)
        _Section(title: 'Dietary', child: _BulletList(items: product.dietaryAttributes)),
      if (product.nutritionalBenefits.isNotEmpty)
        _Section(title: 'NUTRITION', child: _BulletList(items: product.nutritionalBenefits)),
      if (_clean(product.description) != null)
        _Section(title: 'DESCRIPTION', initiallyExpanded: true, child: _Body(text: _clean(product.description)!)),
      if (_clean(product.specifications) != null)
        _Section(title: 'SPECIFICATIONS', child: _Body(text: _clean(product.specifications)!)),
      if (_clean(product.ingredients) != null)
        _Section(title: 'INGREDIENTS', child: _Body(text: _clean(product.ingredients)!)),
      if (_clean(product.notes) != null)
        _Section(title: 'NOTES', child: _Body(text: _clean(product.notes)!)),
      if (product.culinarydetails && product.culinaryUses.isNotEmpty)
        _Section(title: 'Ideal for making', child: _BulletList(items: product.culinaryUses)),
      if (_clean(product.storageInstructions) != null)
        _Section(title: 'Storage Conditions', child: _Body(text: _clean(product.storageInstructions)!)),
      if (_clean(product.allergenInformation) != null)
        _Section(title: 'Allergen Information', child: _Body(text: _clean(product.allergenInformation)!)),
      if (_clean(product.certifications) != null)
        _Section(title: 'Certifications', child: _Body(text: _clean(product.certifications)!)),
    ];

    if (detailSubSections.isEmpty) return const SizedBox.shrink();

    final tabs = <({String label, Widget content})>[
      (
        label: 'Product Details',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: detailSubSections,
        ),
      ),
      if (product.ayurvedicproduct)
        (
          label: 'Ayurveda Insights',
          content: _AyurvedaInsightsTab(product: product),
        ),
    ];

    final activeIndex = _selectedTabIndex.clamp(0, tabs.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('product_details_tab_section'),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: AppColors.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tab Bar Header
                Container(
                  key: const ValueKey('product_details_tab_bar'),
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.secondaryBackground,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          InkWell(
                            key: ValueKey('product_details_tab_$i'),
                            onTap: () => setState(() => _selectedTabIndex = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: i == activeIndex ? AppColors.card : Colors.transparent,
                                border: Border(
                                  bottom: BorderSide(
                                    color: i == activeIndex ? AppColors.primaryGreen : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                tabs[i].label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: i == activeIndex ? FontWeight.bold : FontWeight.w600,
                                  color: i == activeIndex ? AppColors.primaryGreen : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Active Tab Body
                tabs[activeIndex].content,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AyurvedaInsightsTab extends StatelessWidget {
  final ProductPerformance product;

  const _AyurvedaInsightsTab({required this.product});

  Widget _buildSubHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dravyagunaFacts = <MapEntry<String, String>>[
      if (product.ayurvedicRasa.isNotEmpty)
        MapEntry('Rasa', product.ayurvedicRasa.join(', ')),
      if (product.ayurvedicGuna.isNotEmpty)
        MapEntry('Guna', product.ayurvedicGuna.join(', ')),
      if (_clean(product.ayurvedicVirya) != null)
        MapEntry('Virya (Potency)', _clean(product.ayurvedicVirya)!),
      if (_clean(product.ayurvedicVipaka) != null)
        MapEntry('Vipaka (Post-Digestive)', _clean(product.ayurvedicVipaka)!),
      if (_clean(product.ayurvedicPrabhava) != null)
        MapEntry('Prabhava (Special Action)', _clean(product.ayurvedicPrabhava)!),
    ];

    final doshaEntries = <MapEntry<String, String>>[
      if (_clean(product.doshaVata) != null)
        MapEntry('Dosha Effect — Vata', _clean(product.doshaVata)!),
      if (_clean(product.doshaPitta) != null)
        MapEntry('Dosha Effect — Pitta', _clean(product.doshaPitta)!),
      if (_clean(product.doshaKapha) != null)
        MapEntry('Dosha Effect — Kapha', _clean(product.doshaKapha)!),
    ];

    final blocks = <Widget>[
      if (_clean(product.ayurvedicClassification) != null) ...[
        _buildSubHeading('Ayurvedic Classification'),
        _Body(text: _clean(product.ayurvedicClassification)!),
      ],
      if (_clean(product.ayurvedicDescription) != null) ...[
        _buildSubHeading('Classical Description'),
        _Body(text: _clean(product.ayurvedicDescription)!),
      ],
      if (dravyagunaFacts.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < dravyagunaFacts.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: AppColors.border),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 175,
                      child: Text(
                        dravyagunaFacts[i].key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        dravyagunaFacts[i].value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
      if (doshaEntries.isNotEmpty) ...[
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < doshaEntries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _DoshaEffectCard(label: doshaEntries[i].key, value: doshaEntries[i].value),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < doshaEntries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _DoshaEffectCard(label: doshaEntries[i].key, value: doshaEntries[i].value),
                  ),
                ],
              ],
            );
          },
        ),
      ],
      if (product.ayurvedicMedicinalUses.isNotEmpty) ...[
        _buildSubHeading('Medicinal Uses'),
        _BulletList(items: product.ayurvedicMedicinalUses),
      ],
      if (product.ayurvedicUsageMethods.isNotEmpty) ...[
        _buildSubHeading('Usage Methods'),
        _BulletList(items: product.ayurvedicUsageMethods),
      ],
      if (_clean(product.ayurvedicDosage) != null) ...[
        _buildSubHeading('Typical Dosage Note'),
        _Body(text: _clean(product.ayurvedicDosage)!),
      ],
      if (product.ayurvedicFormulations.isNotEmpty) ...[
        _buildSubHeading('Classical Formulations'),
        _Body(text: product.ayurvedicFormulations.join(', ')),
      ],
      if (product.ayurvedicPrecautions.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6C280)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF9A6700)),
                  SizedBox(width: 6),
                  Text(
                    'Precautions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9A6700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BulletList(items: product.ayurvedicPrecautions),
            ],
          ),
        ),
      ],
    ];

    if (blocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Ayurveda insights details are not available for this product.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return Padding(
      key: ValueKey('ayurveda_insights_content_${product.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            blocks[i],
          ],
        ],
      ),
    );
  }
}

class _DoshaEffectCard extends StatelessWidget {
  final String label;
  final String value;

  const _DoshaEffectCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;

  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.circle, size: 6, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  items[i],
                  style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  const _Section({required this.title, required this.child, this.initiallyExpanded = false});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: AppColors.primaryGreen,
          title: Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          children: [child],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;

  const _Body({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 14, height: 1.55, color: AppColors.textSecondary));
  }
}

class _FactsTable extends StatelessWidget {
  final List<MapEntry<String, String>> facts;

  const _FactsTable({required this.facts});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final f in facts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(f.key, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: Text(f.value,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────── Related products ───────────────────────────────

class _RelatedProducts extends ConsumerWidget {
  final ProductPerformance product;

  const _RelatedProducts({required this.product});

  Set<String> _cats(ProductPerformance p) => {
        ...?p.categories?.map((c) => c.trim().toLowerCase()),
        ...(p.category ?? '').split(',').map((c) => c.trim().toLowerCase()),
      }..remove('');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).value ?? const <ProductPerformance>[];
    final mine = _cats(product);
    if (mine.isEmpty) return const SizedBox.shrink();

    final related = products
        .where((p) => p.id != product.id && _cats(p).intersection(mine).isNotEmpty)
        .take(10)
        .toList();
    if (related.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Similar Products',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        SizedBox(
          height: 330,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            // ProductCard navigates with context.push('/product-detail/<id>'), opening the related product.
            itemBuilder: (_, i) => SizedBox(width: 180, child: ProductCard(product: related[i])),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
