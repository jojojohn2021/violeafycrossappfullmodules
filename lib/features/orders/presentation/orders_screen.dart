import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';
import '../../preorder/data/models/preorder_models.dart';
import '../../preorder/preorder_module.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    if (isGuest) {
      return Scaffold(
        backgroundColor: AppColors.secondaryBackground,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          title: const Text('My Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text('No past orders placed yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Your order history will appear here.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    final ordersAsync = ref.watch(salesOrdersProvider);
    final preordersAsync = ref.watch(myPreordersProvider);

    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('My Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          IconButton(
            onPressed: () {
              ref.invalidate(salesOrdersProvider);
              ref.invalidate(myPreordersProvider);
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Orders',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async {
          ref.invalidate(salesOrdersProvider);
          ref.invalidate(myPreordersProvider);
        },
        child: ordersAsync.when(
          data: (orders) {
            final preorders = preordersAsync.value?.items ?? const <PreorderBooking>[];
            if (orders.isEmpty && preorders.isEmpty) {
              if (preordersAsync.isLoading) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
              }
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No past orders placed yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        SizedBox(height: 4),
                        Text('Your order history will appear here.', style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (preorders.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pre-Order Bookings',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                      ),
                      TextButton(
                        onPressed: () => context.push('/preorders/history'),
                        child: const Text('My Bookings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...preorders.map((booking) {
                    final receiptOrder = SalesOrder(
                      id: (booking.invoiceId != null && booking.invoiceId!.isNotEmpty)
                          ? booking.invoiceId!
                          : booking.preorderId,
                      orderNumber: booking.preorderId,
                      customerId: booking.customerId,
                      customerName: booking.customerDisplayName,
                      customerCompany: '',
                      products: [
                        SalesProduct(
                          productId: booking.productId,
                          productName: booking.productNameSnapshot,
                          imageUrl: booking.imageUrlSnapshot,
                          quantity: booking.quantity,
                          price: booking.bookingAdvance,
                          isPreorder: true,
                          preorderId: booking.preorderId,
                          onlinePriceSnapshot: booking.onlinePriceSnapshot,
                          totalProductValue: booking.totalProductValue,
                          paymentType: booking.paymentOption.wireValue,
                          paymentTypeLabel: booking.paymentTypeLabel,
                          bookingAdvance: booking.bookingAdvance,
                          remainingBalance: booking.remainingBalance,
                          giftWrap: booking.giftWrap,
                          specialSuggestion: booking.specialSuggestion,
                          expectedDeliveryDate: booking.expectedDeliveryDate,
                          preferredCourierAgent: booking.preferredCourierAgent,
                        ),
                      ],
                      totalValue: booking.bookingAdvance,
                      paymentStatus: booking.paymentStatus.displayLabel,
                      deliveryStatus: booking.bookingStatus.displayLabel,
                      assignedTo: 'Logistics',
                      createdAt: booking.createdAt,
                      paymentMethod: 'Pre-Order Advance',
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pre-Order #${booking.preorderId}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${booking.bookingStatus.displayLabel} • ${booking.paymentStatus.displayLabel}',
                                    style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            if (booking.createdAt.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(booking.createdAt, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                            const Divider(height: 20),
                            Text(
                              '${booking.productNameSnapshot} (Qty: ${booking.quantity})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Total Value: ₹${booking.totalProductValue.toStringAsFixed(2)} • Remaining Balance: ₹${booking.remainingBalance.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Expected Delivery: ${booking.expectedDeliveryDate} • Courier: ${booking.preferredCourierAgent}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Advance: ₹${booking.bookingAdvance.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primaryGreen),
                                ),
                                OutlinedButton(
                                  onPressed: () => context.push('/orders/invoice', extra: receiptOrder),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                  child: const Text('View Receipt', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (orders.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Regular Sales Orders',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                ...orders.map((order) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('#${order.orderNumber.isNotEmpty ? order.orderNumber : order.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  order.deliveryStatus,
                                  style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(order.createdAt, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          const Divider(height: 20),
                          Text(
                            '${order.products.length} items (${order.products.map((p) => p.productName).join(", ")})',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 12),
                          if (order.totalTaxableValue != null && order.totalGstAmount != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Taxable: ₹${order.totalTaxableValue!.toStringAsFixed(2)} | GST: ₹${order.totalGstAmount!.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                const Text(
                                  'Incl. GST',
                                  style: TextStyle(fontSize: 10, color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total: ₹${order.totalValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primaryGreen)),
                              OutlinedButton(
                                onPressed: () => context.push('/orders/invoice', extra: order),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                ),
                                child: const Text('View Invoice', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
          error: (err, _) => Center(child: Text('Error loading orders: $err')),
        ),
      ),
    );
  }
}
