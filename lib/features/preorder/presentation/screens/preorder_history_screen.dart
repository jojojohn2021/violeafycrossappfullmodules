import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/models.dart';
import '../../../../providers/app_providers.dart';
import '../../../cart_checkout/domain/payment_orchestrator.dart';
import '../../data/models/preorder_models.dart';
import '../../preorder_module.dart';
import '../widgets/preorder_widgets.dart';

/// Authenticated User's Pre-Order Bookings History (`/preorders/history`)
class PreorderHistoryScreen extends ConsumerWidget {
  const PreorderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myPreordersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Bookings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          IconButton(
            onPressed: () => ref.invalidate(myPreordersProvider),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Bookings',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async {
          ref.invalidate(myPreordersProvider);
        },
        child: bookingsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          ),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42, color: AppColors.error),
                  const SizedBox(height: 10),
                  Text(
                    'Failed to load pre-order bookings:\n${err.toString().replaceFirst("ServerException: ", "")}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(myPreordersProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (paged) {
            final items = paged.items;
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  const SizedBox(height: 48),
                  const Icon(Icons.event_note_outlined, size: 52, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text(
                    'No Pre-Order Bookings Yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your pre-order advance bookings will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => context.go('/preorders'),
                      child: const Text('Browse Pre-Order Products'),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final booking = items[index];
                return InkWell(
                  onTap: () => context.push('/preorders/detail/${Uri.encodeComponent(booking.preorderId)}'),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
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
                            Expanded(
                              child: Text(
                                'Ref: ${booking.preorderId}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Wrap(
                              spacing: 6,
                              children: [
                                PreorderPaymentStatusBadge(paymentStatus: booking.paymentStatus),
                                PreorderStatusBadge(status: booking.bookingStatus),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 18, color: AppColors.border),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 52,
                                height: 52,
                                color: AppColors.secondaryBackground,
                                padding: const EdgeInsets.all(4),
                                child: booking.imageUrlSnapshot != null &&
                                        booking.imageUrlSnapshot!.startsWith('http')
                                    ? CachedNetworkImage(
                                        imageUrl: booking.imageUrlSnapshot!,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.image_not_supported_outlined, size: 20),
                                      )
                                    : const Icon(Icons.image_not_supported_outlined, size: 20),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.productNameSnapshot,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Qty: ${booking.quantity} • ${booking.paymentTypeLabel} • Delivery: ${booking.expectedDeliveryDate}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Courier: ${booking.preferredCourierAgent} • Gift Wrap: ${booking.giftWrap ? "Yes" : "No"}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                  if (booking.isConvertedToSalesOrder) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sales Order: ${booking.salesOrderNumber ?? booking.salesOrderId} • PRE-ORDER',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryGreen,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  booking.totalVerifiedPaid > booking.initialBookingAdvance
                                      ? 'Paid: ₹${booking.totalVerifiedPaid.toStringAsFixed(2)}'
                                      : 'Adv: ₹${booking.initialBookingAdvance.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Bal: ₹${booking.remainingBalance.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Single Pre-Order Booking Confirmation & Status Detail Screen (`/preorders/detail/:preorderId`)
class PreorderDetailScreen extends ConsumerStatefulWidget {
  final String preorderId;

  const PreorderDetailScreen({super.key, required this.preorderId});

  @override
  ConsumerState<PreorderDetailScreen> createState() => _PreorderDetailScreenState();
}

class _PreorderDetailScreenState extends ConsumerState<PreorderDetailScreen> {
  final _orchestrator = PaymentOrchestrator();
  bool _isPayingBalance = false;

  Future<void> _payRemainingBalance(PreorderBooking booking) async {
    if (_isPayingBalance || !booking.canPayRemainingBalance) return;

    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      if (mounted) {
        context.go('/login?redirect=${Uri.encodeComponent('/preorders/detail/${booking.preorderId}')}');
      }
      return;
    }

    setState(() => _isPayingBalance = true);
    try {
      String customerName = booking.customerDisplayName.trim();
      String customerEmail = user.email?.trim() ?? '';
      String customerMobile = user.phoneNumber?.trim() ?? '';

      try {
        final customer = await ref.read(shoppingRepositoryProvider).getCurrentCustomer();
        if (customer != null) {
          if (customerName.isEmpty && customer.name.trim().isNotEmpty) {
            customerName = customer.name.trim();
          }
          if (customerEmail.isEmpty && customer.email.trim().isNotEmpty) {
            customerEmail = customer.email.trim();
          }
          if (customerMobile.isEmpty && customer.mobileNumber.trim().isNotEmpty) {
            customerMobile = customer.mobileNumber.trim();
          }
        }
      } catch (_) {}

      if (customerName.isEmpty) {
        customerName = 'LeafyEarth Customer';
      }

      final deliveryAddressJson =
          booking.deliveryAddress?.toJson() ?? ref.read(selectedAddressProvider)?.toJson();

      // Request authoritative balance checkout quote from backend
      final quote = await ref.read(preorderServiceProvider).createBalanceCheckout(
            preorderId: booking.preorderId,
            deliveryAddress: deliveryAddressJson,
          );

      final balanceAmount = quote.payableAmount > 0 ? quote.payableAmount : booking.remainingBalance;
      final serverOrderData = quote.orderData;
      final orderId = (serverOrderData['id']?.toString().isNotEmpty == true)
          ? serverOrderData['id'].toString()
          : (quote.checkoutId.isNotEmpty
              ? quote.checkoutId
              : 'BAL-${booking.preorderId}-${DateTime.now().millisecondsSinceEpoch}');

      final orderData = <String, dynamic>{
        ...serverOrderData,
        'id': orderId,
        'orderNumber': serverOrderData['orderNumber'] ?? booking.preorderId,
        'customerId': user.uid,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerMobile': sanitizeMobileNumber(customerMobile),
        'customerCompany': '',
        if (deliveryAddressJson != null) 'shippingAddress': deliveryAddressJson,
        if (deliveryAddressJson != null) 'deliveryAddress': deliveryAddressJson,
        'isPreorderBalancePayment': true,
        'preorderId': booking.preorderId,
        'totalPreorderBookingAdvance': balanceAmount,
        'customerGrandTotalPayable': balanceAmount,
        'totalValue': balanceAmount,
        'salesPlatform': kIsWeb ? 'webleafyearth' : 'mobleafyearth',
      };

      if (!mounted) return;
      final result = await _orchestrator.pay(
        orderData: orderData,
        environment: 'Live',
        context: context,
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();

      switch (result.outcome) {
        case PaymentOutcome.launchedExternally:
          break;
        case PaymentOutcome.success:
          ref.invalidate(preorderDetailProvider(widget.preorderId));
          ref.invalidate(myPreordersProvider);
          ref.invalidate(salesOrdersProvider);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                'Remaining balance of ₹${balanceAmount.toStringAsFixed(2)} paid successfully!',
              ),
              backgroundColor: AppColors.primaryGreen,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          Future.delayed(const Duration(seconds: 3), () {
            messenger?.hideCurrentSnackBar();
          });
          break;
        case PaymentOutcome.cancelled:
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Remaining balance payment was cancelled.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
          break;
        case PaymentOutcome.failed:
        case PaymentOutcome.initFailed:
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Remaining balance payment could not be completed. Please try again.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Payment error: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPayingBalance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(preorderDetailProvider(widget.preorderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Pre-Order Booking Details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          IconButton(
            onPressed: () => ref.invalidate(preorderDetailProvider(widget.preorderId)),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Unable to load booking: ${err.toString().replaceFirst("ServerException: ", "")}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
        data: (booking) {
          final invoiceRef = booking.invoiceId ?? booking.checkoutReference ?? booking.preorderId;
          final hasPaidAdvance = booking.paymentStatus == PreorderPaymentStatus.paid ||
              booking.paymentStatus == PreorderPaymentStatus.partiallyPaid;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Booking Status',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              PreorderPaymentStatusBadge(paymentStatus: booking.paymentStatus),
                              PreorderStatusBadge(status: booking.bookingStatus),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Booking Reference: ${booking.preorderId}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const Divider(height: 24, color: AppColors.border),
                      Text(
                        booking.productNameSnapshot,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (booking.packingSizeSnapshot.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Pack Size: ${booking.packingSizeSnapshot}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _DetailLine(label: 'Booking Reference', value: booking.preorderId),
                      _DetailLine(label: 'Quantity', value: '${booking.quantity}'),
                      _DetailLine(
                        label: 'Online Price',
                        value: '₹${booking.onlinePriceSnapshot.toStringAsFixed(2)}',
                      ),
                      _DetailLine(
                        label: 'Total Product Value',
                        value: '₹${booking.totalProductValue.toStringAsFixed(2)}',
                      ),
                      _DetailLine(label: 'Payment Type', value: booking.paymentTypeLabel),
                      _DetailLine(
                        label: 'Booking Advance Paid',
                        value: '₹${booking.initialBookingAdvance.toStringAsFixed(2)}',
                        highlight: true,
                      ),
                      if (booking.totalVerifiedPaid > booking.initialBookingAdvance)
                        _DetailLine(
                          label: 'Total Verified Paid',
                          value: '₹${booking.totalVerifiedPaid.toStringAsFixed(2)}',
                          highlight: true,
                        ),
                      _DetailLine(
                        label: 'Remaining Balance',
                        value: '₹${booking.remainingBalance.toStringAsFixed(2)}',
                      ),
                      _DetailLine(label: 'Payment Status', value: booking.paymentStatus.displayLabel),
                      _DetailLine(label: 'Booking Status', value: booking.bookingStatus.displayLabel),
                      _DetailLine(
                        label: 'Sales Order Conversion',
                        value: booking.conversionStatusLabel,
                        highlight: booking.isConvertedToSalesOrder,
                      ),
                      if (booking.isConvertedToSalesOrder) ...[
                        _DetailLine(
                          label: 'Linked Sales Order',
                          value: booking.salesOrderNumber ?? booking.salesOrderId ?? '',
                          highlight: true,
                        ),
                        const _DetailLine(
                          label: 'Sales Delivery Status',
                          value: 'PRE-ORDER',
                        ),
                      ],
                      _DetailLine(label: 'Gift Wrap', value: booking.giftWrap ? 'Yes' : 'No'),
                      _DetailLine(
                        label: 'Special Suggestion',
                        value: booking.specialSuggestion.isEmpty ? 'None' : booking.specialSuggestion,
                      ),
                      _DetailLine(label: 'Expected Date of Delivery', value: booking.expectedDeliveryDate),
                      _DetailLine(label: 'Preferred Courier Agent', value: booking.preferredCourierAgent),
                      if (booking.formattedDeliveryAddress.isNotEmpty)
                        _DetailLine(
                          label: 'Delivery Address',
                          value: booking.formattedDeliveryAddress,
                        ),
                      const SizedBox(height: 18),
                      if (booking.canPayRemainingBalance) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            key: const ValueKey('preorder_pay_remaining_balance_btn'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _isPayingBalance ? null : () => _payRemainingBalance(booking),
                            icon: _isPayingBalance
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.payment_outlined, size: 18),
                            label: Text(
                              _isPayingBalance
                                  ? 'STARTING PAYMENT...'
                                  : 'Pay Remaining Balance (₹${booking.remainingBalance.toStringAsFixed(2)})',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (hasPaidAdvance) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryGreen,
                              side: const BorderSide(color: AppColors.primaryGreen),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => context.push(
                              '/orders/invoice',
                              extra: SalesOrder(
                                id: invoiceRef,
                                orderNumber: booking.checkoutReference ?? booking.preorderId,
                                customerId: booking.userId,
                                customerName: booking.customerDisplayName.isNotEmpty
                                    ? booking.customerDisplayName
                                    : 'Customer',
                                customerCompany: '',
                                products: const [],
                                totalValue: booking.bookingAdvance,
                                paymentStatus: booking.paymentStatus == PreorderPaymentStatus.paid
                                    ? 'Paid'
                                    : 'Partially Paid',
                                deliveryStatus: booking.bookingStatus.displayLabel,
                                assignedTo: booking.preferredCourierAgent,
                                createdAt: booking.createdAt,
                                paymentMethod: 'Online',
                              ),
                            ),
                            icon: const Icon(Icons.receipt_long_outlined, size: 18),
                            label: const Text('View Advance Receipt / Invoice'),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                            side: const BorderSide(color: AppColors.primaryGreen),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => context.go('/preorders/history'),
                          child: const Text('View All Pre-Order Bookings'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _DetailLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: highlight ? 15 : 13,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                color: highlight ? AppColors.primaryGreen : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
