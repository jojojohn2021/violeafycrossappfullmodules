import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
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

  void _applyCoupon() {
    final code = _couponController.text.trim().toUpperCase();
    if (code == 'MANGO25' || code == 'LEAFY50') {
      setState(() {
        _couponApplied = true;
        _couponDiscount = 50.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Coupon "$code" applied successfully! Saved ₹50')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid promo code')),
      );
    }
  }

  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    final subtotal = cartNotifier.totalPrice;
    const deliveryFee = 30.0;
    final totalPayable = (subtotal + deliveryFee - _couponDiscount).clamp(0.0, double.infinity);

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
                        // Cart Items List
                        Container(
                          color: AppColors.card,
                          padding: const EdgeInsets.all(12),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cart.length,
                            separatorBuilder: (_, __) => const Divider(height: 20),
                            itemBuilder: (context, index) {
                              final item = cart[index];
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
                        ),

                        const SizedBox(height: 12),

                        // Coupon Applicator
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
                                    onPressed: _applyCoupon,
                                    child: Text(_couponApplied ? 'APPLIED' : 'APPLY'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Payment Summary Breakdown
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
                                  const Text('Item Subtotal', style: TextStyle(color: AppColors.textSecondary)),
                                  Text('₹${subtotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Delivery Fee', style: TextStyle(color: AppColors.textSecondary)),
                                  Text('₹${deliveryFee.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              if (_couponDiscount > 0) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Coupon Discount', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                                    Text('-₹${_couponDiscount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('₹${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryGreen)),
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
                            const Text('TOTAL PAYABLE', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            Text('₹${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _isNavigating ? null : () async {
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
                          },
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
