import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/product_story_dialog.dart';

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

      final content = isWide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Breadcrumb(product: product),
                const SizedBox(height: 16),
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
                related,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                gallery,
                const SizedBox(height: 16),
                info,
                const SizedBox(height: 8),
                details,
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
          if (!isWide) _BottomPurchaseBar(product: product),
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
            Positioned(
              left: 10,
              bottom: 10,
              child: Material(
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
        // 2. Pack size
        if (packSize != null) ...[
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
        // 9. Stock (existing field, shown only when set)
        if (stockText != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(stockText,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ],
        // 10. Purchase controls (wide layouts; mobile uses the bottom bar)
        if (showInlinePurchase) ...[
          const SizedBox(height: 20),
          SizedBox(width: 280, child: _CartControl(product: product, height: 48)),
        ],
      ],
    );
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

class _ProductDetailsSections extends StatelessWidget {
  final ProductPerformance product;

  const _ProductDetailsSections({required this.product});

  @override
  Widget build(BuildContext context) {
    final category = _clean(product.categories?.isNotEmpty == true ? product.categories!.join(', ') : product.category);
    final facts = <MapEntry<String, String>>[
      if (_clean(product.brand) != null) MapEntry('Brand', _clean(product.brand)!),
      if (category != null) MapEntry('Category', category),
      if (_clean(product.packingSize) != null) MapEntry('Pack Size', _clean(product.packingSize)!),
      if (_clean(product.unit) != null) MapEntry('Unit', _clean(product.unit)!),
      if (_clean(product.variants) != null) MapEntry('Variants', _clean(product.variants)!),
      if (_clean(product.brandOwner) != null) MapEntry('Marketed By', _clean(product.brandOwner)!),
    ];

    final sections = <Widget>[
      if (facts.isNotEmpty) _Section(title: 'Product Details', initiallyExpanded: true, child: _FactsTable(facts: facts)),
      if (_clean(product.description) != null)
        _Section(title: 'Description', initiallyExpanded: true, child: _Body(text: _clean(product.description)!)),
      if (_clean(product.specifications) != null)
        _Section(title: 'Specifications', child: _Body(text: _clean(product.specifications)!)),
      if (_clean(product.ingredients) != null)
        _Section(title: 'Ingredients', child: _Body(text: _clean(product.ingredients)!)),
    ];

    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: sections),
        ),
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
    final products = ref.watch(productsProvider).valueOrNull ?? const <ProductPerformance>[];
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
