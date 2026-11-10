import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/models.dart';
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
          'My Pre-Order Bookings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Adv: ₹${booking.bookingAdvance.toStringAsFixed(2)}',
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
  bool _cancelling = false;

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Pre-Order Booking?'),
        content: const Text(
          'Are you sure you want to cancel this pre-order booking?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep Booking')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(preorderServiceProvider).cancelBooking(
            preorderId: widget.preorderId,
            reason: 'Cancelled by customer',
          );
      if (!mounted) return;
      ref.invalidate(preorderDetailProvider(widget.preorderId));
      ref.invalidate(myPreordersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pre-order booking cancelled.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('ServerException: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
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
                        value: '₹${booking.bookingAdvance.toStringAsFixed(2)}',
                        highlight: true,
                      ),
                      _DetailLine(
                        label: 'Remaining Balance',
                        value: '₹${booking.remainingBalance.toStringAsFixed(2)}',
                      ),
                      _DetailLine(label: 'Payment Status', value: booking.paymentStatus.displayLabel),
                      _DetailLine(label: 'Booking Status', value: booking.bookingStatus.displayLabel),
                      _DetailLine(label: 'Gift Wrap', value: booking.giftWrap ? 'Yes' : 'No'),
                      _DetailLine(
                        label: 'Special Suggestion',
                        value: booking.specialSuggestion.isEmpty ? 'None' : booking.specialSuggestion,
                      ),
                      _DetailLine(label: 'Expected Date of Delivery', value: booking.expectedDeliveryDate),
                      _DetailLine(label: 'Preferred Courier Agent', value: booking.preferredCourierAgent),
                      const SizedBox(height: 18),
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
                      if (booking.canCancel) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _cancelling ? null : _confirmCancel,
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: Text(_cancelling ? 'Cancelling...' : 'Cancel Pre-Order Booking'),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
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
