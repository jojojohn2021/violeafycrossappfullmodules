import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/gst_calculator.dart';
import '../../../../models/models.dart';
import '../../../../providers/app_providers.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final TextEditingController _couponController = TextEditingController();
  bool _couponApplied = false;
  double _couponDiscount = 0.0;
  String? _appliedCouponCode;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      }
      _initAddress();
    });
  }

  Future<void> _proceedToCheckout() async {
    if (_isNavigating) return;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    final redirect = Uri.encodeComponent('/checkout');
    if (firebase_auth.FirebaseAuth.instance.currentUser == null) {
      context.go('/login?redirect=$redirect');
    } else {
      setState(() => _isNavigating = true);
      try {
        await context.push('/checkout');
      } finally {
        if (mounted) setState(() => _isNavigating = false);
      }
    }
  }

  Future<void> _initAddress() async {
    var selected = ref.read(selectedAddressProvider);
    if (selected == null) {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final addresses = await ref.read(shoppingRepositoryProvider).getCustomerAddresses(user.uid);
          if (addresses.isNotEmpty && mounted) {
            final defaultAddr = addresses.firstWhere(
              (a) => a.isDefault,
              orElse: () => addresses.first,
            );
            ref.read(selectedAddressProvider.notifier).state = defaultAddr;
            selected = defaultAddr;
          }
        } catch (_) {}
      }
    }
  }

  void _applyCoupon(List<Coupon> availableCoupons, double regularSubtotal, double currentDeliveryFee) {
    final code = _couponController.text.trim().toUpperCase();
    Coupon? match;
    for (final coupon in availableCoupons) {
      if (coupon.code.trim().toUpperCase() == code) {
        match = coupon;
        break;
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or unavailable promo code')),
      );
      return;
    }
    if (match.minOrderValue != null && regularSubtotal < match.minOrderValue!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add regular sales items worth ₹${match.minOrderValue!.toStringAsFixed(0)} or more to use this code')),
      );
      return;
    }

    double discount;
    switch (match.type) {
      case 'percentage':
        discount = regularSubtotal * (match.value / 100);
        if (match.maxDiscount != null && discount > match.maxDiscount!) {
          discount = match.maxDiscount!;
        }
        break;
      case 'free_shipping':
        discount = currentDeliveryFee;
        break;
      default:
        discount = match.value;
    }

    setState(() {
      _couponApplied = true;
      _appliedCouponCode = match!.code;
      _couponDiscount = discount;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coupon "${match.code}" applied successfully! Saved ₹${discount.toStringAsFixed(0)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final couponsAsync = ref.watch(couponsProvider);
    final availableCoupons = couponsAsync.value ?? const <Coupon>[];

    final selectedAddress = ref.watch(selectedAddressProvider);
    final deliveryChargeState = ref.watch(deliveryChargeProvider);

    final regularItems = cart.where((item) => !item.isPreorder).toList();
    final preorderItems = cart.where((item) => item.isPreorder).toList();

    final regularDeliveryFee = regularItems.isNotEmpty ? deliveryChargeState.deliveryCharge : 0.0;
    final gstCartSummary = GstCalculator.calculateCartSummary(
      cart,
      deliveryFee: regularDeliveryFee,
      discount: regularItems.isNotEmpty ? _couponDiscount : 0.0,
    );

    final regularSubtotal = gstCartSummary.regularSalesSubtotal;
    final regularInvoiceGrandTotal = gstCartSummary.regularInvoiceGrandTotal;
    final totalPreorderAdvance = gstCartSummary.totalPreorderBookingAdvance;
    final totalPayable = gstCartSummary.customerGrandTotalPayable;

    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('Shopping Cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shopping_bag_outlined, size: 56, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your cart is empty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text('Looks like you haven\'t added anything yet.', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Explore Fresh Catalog'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Regular Sales Items Section (Always Displayed First)
                        if (regularItems.isNotEmpty) ...[
                          Container(
                            color: AppColors.card,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (preorderItems.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      'REGULAR SALES ITEMS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.4,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: regularItems.length,
                                  separatorBuilder: (_, __) => const Divider(height: 20),
                                  itemBuilder: (context, index) {
                                    final item = regularItems[index];
                                    return Row(
                                      children: [
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: AppColors.secondaryBackground,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                                              ? CachedNetworkImage(
                                                  imageUrl: item.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => const Icon(
                                                    Icons.image_not_supported_outlined,
                                                    color: AppColors.textMuted,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.image_not_supported_outlined,
                                                  color: AppColors.textMuted,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.productName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '₹${item.price.toStringAsFixed(0)} each',
                                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                              ),
                                              const SizedBox(height: 2),
                                              Builder(builder: (context) {
                                                final calc = GstCalculator.calculateItemGst(
                                                  price: item.price,
                                                  quantity: item.quantity,
                                                  gstPercentage: item.gstPercentage,
                                                  hsnCode: item.hsnCode,
                                                );
                                                final rate = calc['gstRate'] as double;
                                                final gstVal = calc['gstAmount'] as double;
                                                return Text(
                                                  'GST ${rate.toStringAsFixed(rate % 1 != 0 ? 1 : 0)}% (₹${gstVal.toStringAsFixed(2)})',
                                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.secondaryBackground,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppColors.border),
                                          ),
                                          child: Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () => cartNotifier.updateQuantity(item.productId, item.quantity - 1),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  child: Icon(Icons.remove, size: 16),
                                                ),
                                              ),
                                              Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                              GestureDetector(
                                                onTap: () => cartNotifier.updateQuantity(item.productId, item.quantity + 1),
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  child: Icon(Icons.add, size: 16),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // 2. Pre-Order Booking Items Section (Displayed Below Regular Sales Items)
                        if (preorderItems.isNotEmpty) ...[
                          Container(
                            color: AppColors.card,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.event_available_outlined, size: 16, color: AppColors.primaryGreen),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'PRE-ORDER BOOKING ITEMS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.4,
                                        color: AppColors.primaryGreen,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Pre-order booking advances are collected now and excluded from regular sales GST calculations.',
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                const Divider(height: 18),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: preorderItems.length,
                                  separatorBuilder: (_, __) => const Divider(height: 20),
                                  itemBuilder: (context, index) {
                                    final item = preorderItems[index];
                                    final onlinePrice = item.onlinePriceSnapshot ?? item.price;
                                    final totalProdVal = item.totalProductValue ?? (onlinePrice * item.quantity);
                                    final advance = item.bookingAdvance ?? item.effectivePayableAmount;
                                    final balance = item.remainingBalance ?? (totalProdVal - advance);

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: AppColors.secondaryBackground,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                                                  ? CachedNetworkImage(
                                                      imageUrl: item.imageUrl!,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (_, __, ___) => const Icon(
                                                        Icons.image_not_supported_outlined,
                                                        color: AppColors.textMuted,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.image_not_supported_outlined,
                                                      color: AppColors.textMuted,
                                                    ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.productName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    'Booking Ref: ${item.preorderId ?? "-"} • Qty: ${item.quantity}',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Online Price: ₹${onlinePrice.toStringAsFixed(2)} • Total Value: ₹${totalProdVal.toStringAsFixed(2)}',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${item.paymentTypeLabel ?? "Booking Advance"} • Advance: ₹${advance.toStringAsFixed(2)} • Balance: ₹${balance.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.primaryGreen,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Expected Delivery: ${item.expectedDeliveryDate ?? "-"} • Courier: ${item.preferredCourierAgent ?? "-"} • Gift Wrap: ${item.giftWrap == true ? "Yes" : "No"}',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  ),
                                                  if (item.specialSuggestion != null && item.specialSuggestion!.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Suggestion: ${item.specialSuggestion}',
                                                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '₹${advance.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: AppColors.primaryGreen,
                                                  ),
                                                ),
                                                const Text(
                                                  'Advance',
                                                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                                ),
                                                const SizedBox(height: 6),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: AppColors.secondaryBackground,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: AppColors.border),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () => cartNotifier.updateQuantity(item.productId, item.quantity - 1),
                                                        child: const Padding(
                                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          child: Icon(Icons.remove, size: 16),
                                                        ),
                                                      ),
                                                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                      GestureDetector(
                                                        onTap: item.quantity < 20
                                                            ? () => cartNotifier.updateQuantity(item.productId, item.quantity + 1)
                                                            : null,
                                                        child: const Padding(
                                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          child: Icon(Icons.add, size: 16),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Coupon Applicator - hidden entirely when no active coupons exist or no regular items
                        if (availableCoupons.isNotEmpty && regularItems.isNotEmpty) ...[
                          Container(
                            color: AppColors.card,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Apply Coupon / Promo Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _couponController,
                                        decoration: const InputDecoration(
                                          hintText: 'Enter code',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      onPressed: () => _applyCoupon(availableCoupons, regularSubtotal, regularDeliveryFee),
                                      child: Text(_couponApplied ? 'APPLIED' : 'APPLY'),
                                    ),
                                  ],
                                ),
                                if (_couponApplied && _appliedCouponCode != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Code "$_appliedCouponCode" applied', style: const TextStyle(color: AppColors.primaryGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Delivery Address Selection Summary
                        Container(
                          color: AppColors.card,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 20, color: AppColors.primaryGreen),
                                      SizedBox(width: 6),
                                      Text('Delivery Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () => context.push('/checkout'),
                                    child: Text(selectedAddress == null ? 'SELECT' : 'CHANGE'),
                                  ),
                                ],
                              ),
                              if (selectedAddress != null) ...[
                                Text(
                                  '${selectedAddress.name} (${selectedAddress.pincode})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Text(
                                  '${selectedAddress.addressLine}, ${selectedAddress.city}, ${selectedAddress.state}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ] else ...[
                                const Text(
                                  'No address selected. Delivery fee defaults to Free Delivery (₹0).',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Payment Summary Breakdown (Section 5 & Section 6.3 Rules)
                        Container(
                          color: AppColors.card,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bill Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Regular Sales Subtotal', style: TextStyle(color: AppColors.textSecondary)),
                                  Text('₹${regularSubtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Regular Taxable Value (excl. GST)', style: TextStyle(color: AppColors.textSecondary)),
                                  Text('₹${gstCartSummary.totalTaxableValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('GST on Regular Sales', style: TextStyle(color: AppColors.textSecondary)),
                                  Text('₹${gstCartSummary.totalGstAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              if (regularItems.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Delivery Fee', style: TextStyle(color: AppColors.textSecondary)),
                                    if (deliveryChargeState.isLoading)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                                      )
                                    else
                                      Text(
                                        regularDeliveryFee == 0 ? 'Free Delivery' : '₹${regularDeliveryFee.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: regularDeliveryFee == 0 ? AppColors.primaryGreen : AppColors.textPrimary,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              if (_couponDiscount > 0 && regularItems.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Coupon Discount', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                                    Text('-₹${_couponDiscount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                              if (gstCartSummary.hsnSummary.isNotEmpty) ...[
                                const Divider(height: 24),
                                const Text('HSN-Wise GST Breakdown (Regular Sales)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(1.2),
                                      1: FlexColumnWidth(1),
                                      2: FlexColumnWidth(1.4),
                                      3: FlexColumnWidth(1.3),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: const BoxDecoration(color: AppColors.secondaryBackground),
                                        children: const [
                                          Padding(padding: EdgeInsets.all(6), child: Text('HSN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                          Padding(padding: EdgeInsets.all(6), child: Text('Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                          Padding(padding: EdgeInsets.all(6), child: Text('Taxable', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                          Padding(padding: EdgeInsets.all(6), child: Text('GST Amt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                        ],
                                      ),
                                      for (final item in gstCartSummary.hsnSummary)
                                        TableRow(
                                          children: [
                                            Padding(padding: const EdgeInsets.all(6), child: Text(item.hsnCode, style: const TextStyle(fontSize: 11))),
                                            Padding(padding: const EdgeInsets.all(6), child: Text('${item.gstRate.toStringAsFixed(item.gstRate % 1 != 0 ? 1 : 0)}%', style: const TextStyle(fontSize: 11))),
                                            Padding(padding: const EdgeInsets.all(6), child: Text('₹${item.taxableValue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11))),
                                            Padding(padding: const EdgeInsets.all(6), child: Text('₹${item.gstAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('REGULAR INVOICE GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('₹${regularInvoiceGrandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              if (preorderItems.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Pre-Order Booking Advance', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600, fontSize: 13)),
                                    Text('₹${totalPreorderAdvance.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ],
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('CUSTOMER GRAND TOTAL PAYABLE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text('₹${totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryGreen)),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Bottom Checkout CTA
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CUSTOMER GRAND TOTAL PAYABLE', style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                            Text('₹${totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          ],
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('cart_bottom_proceed_to_pay_btn'),
                          onPressed: _isNavigating ? null : _proceedToCheckout,
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text('PROCEED TO PAY'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
