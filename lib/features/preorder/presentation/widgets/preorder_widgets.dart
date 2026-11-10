import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_errors.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/models.dart';
import '../../../../providers/app_providers.dart';
import '../../data/models/preorder_models.dart';
import '../../domain/preorder_service.dart';
import '../../preorder_module.dart';

/// Complete Pre-Order Booking Details section & PRE-ORDER BOOKING purchase action
/// rendered directly below In Stock information on [ProductDetailScreen]
/// ONLY when `product.preorderactive == true` (Boolean).
class PreorderBookingDetailsSection extends ConsumerStatefulWidget {
  final ProductPerformance product;

  const PreorderBookingDetailsSection({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<PreorderBookingDetailsSection> createState() =>
      _PreorderBookingDetailsSectionState();
}

class _PreorderBookingDetailsSectionState
    extends ConsumerState<PreorderBookingDetailsSection> {
  int _quantity = 1;
  PreorderPaymentOption _paymentOption = PreorderPaymentOption.full;
  final TextEditingController _partialAdvanceController =
      TextEditingController();
  final TextEditingController _specialSuggestionController =
      TextEditingController();
  bool _giftWrap = false;
  late DateTime _expectedDeliveryDate;
  String _preferredCourierAgent = PreorderService.defaultCourierAgents.first;
  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _expectedDeliveryDate = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 3));
    final unitPrice = _onlinePrice;
    final defaultMin = roundPreorderCurrency(unitPrice * 0.10);
    _partialAdvanceController.text = defaultMin.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _partialAdvanceController.dispose();
    _specialSuggestionController.dispose();
    super.dispose();
  }

  double get _onlinePrice {
    final p = widget.product;
    return (p.offerPrice != null && p.offerPrice! > 0)
        ? p.offerPrice!
        : p.onlinePrice;
  }

  PreorderAdvanceValidationResult _computeAdvanceResult(int effectiveQty) {
    return PreorderAdvanceValidator.validateAndCalculate(
      onlinePrice: _onlinePrice,
      quantity: effectiveQty,
      paymentOption: _paymentOption,
      partialInputText: _partialAdvanceController.text,
    );
  }

  PreorderAdvanceValidationResult get _advanceResult =>
      _computeAdvanceResult(_quantity);

  void _updateBookedQuantity(int currentQty, int nextQty) {
    final notifier = ref.read(cartProvider.notifier);
    if (nextQty <= 0) {
      notifier.removeFromCart(widget.product.id);
      setState(() {
        _quantity = 1;
        final defaultMin = roundPreorderCurrency(_onlinePrice * 0.10);
        _partialAdvanceController.text = defaultMin.toStringAsFixed(2);
        _formError = null;
      });
      return;
    }

    if (_paymentOption == PreorderPaymentOption.partial && currentQty > 0) {
      final currentParsed =
          double.tryParse(_partialAdvanceController.text.trim()) ??
              roundPreorderCurrency(_onlinePrice * currentQty * 0.10);
      final perUnitAdvance = currentParsed / currentQty;
      final scaledAdvance = roundPreorderCurrency(perUnitAdvance * nextQty);
      _partialAdvanceController.text = scaledAdvance.toStringAsFixed(2);
    }

    setState(() {
      _quantity = nextQty;
      _formError = null;
    });
    notifier.updateQuantity(widget.product.id, nextQty);
  }

  Future<void> _pickExpectedDeliveryDate() async {
    final now = DateTime.now();
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final maxDate = tomorrow.add(const Duration(days: 365));
    final initial = _expectedDeliveryDate.isAfter(tomorrow)
        ? _expectedDeliveryDate
        : tomorrow;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: tomorrow,
      lastDate: maxDate,
      helpText: 'SELECT EXPECTED DATE OF DELIVERY (FUTURE DATES ONLY)',
    );
    if (picked != null && mounted) {
      setState(() {
        _expectedDeliveryDate = picked;
        _formError = null;
      });
    }
  }

  Future<void> _handlePreorderBooking() async {
    if (_submitting) return;
    if (!PreorderService.isProductEligible(widget.product)) {
      setState(() {
        _formError = 'This product is not eligible for pre-order booking.';
      });
      return;
    }

    final validation = _advanceResult;
    if (!validation.isValid) {
      setState(() {
        _formError =
            validation.errorMessage ?? 'Please enter a valid Booking Advance.';
      });
      return;
    }

    if (!PreorderAdvanceValidator.isFutureDeliveryDate(_expectedDeliveryDate)) {
      setState(() {
        _formError =
            'Expected Date of Delivery must be a future date (after today).';
      });
      return;
    }

    if (_preferredCourierAgent.trim().isEmpty) {
      setState(() {
        _formError = 'Please select a Preferred Courier Agent.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });

    final expectedDateStr =
        PreorderAdvanceValidator.formatDateYyyyMmDd(_expectedDeliveryDate);
    final sanitizedSuggestion = _specialSuggestionController.text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
    final idemKey = PreorderService.generateIdempotencyKey(widget.product.id);

    try {
      final result =
          await ref.read(preorderServiceProvider).createPreorderBooking(
                productId: widget.product.id,
                quantity: _quantity,
                paymentOption: _paymentOption,
                bookingAdvance: validation.bookingAdvance,
                giftWrap: _giftWrap,
                specialSuggestion: sanitizedSuggestion,
                expectedDeliveryDate: expectedDateStr,
                preferredCourierAgent: _preferredCourierAgent,
                idempotencyKey: idemKey,
              );

      if (!mounted) return;
      final cartItem = PreorderService.toPreorderCartItem(result.booking);
      ref.read(cartProvider.notifier).addPreorderToCart(cartItem);
      ref.invalidate(myPreordersProvider);

      setState(() => _submitting = false);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Pre-order booking (${result.booking.preorderId}) added to cart. '
              'Advance payable: ₹${result.booking.bookingAdvance.toStringAsFixed(2)}',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      Future.delayed(const Duration(seconds: 3), () {
        messenger?.hideCurrentSnackBar();
      });
    } on AuthException {
      if (!mounted) return;
      setState(() => _submitting = false);
      final redirect =
          Uri.encodeComponent('/product-detail/${widget.product.id}');
      context.push('/login?redirect=$redirect');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = e.toString().replaceFirst('ServerException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PreorderService.isProductEligible(widget.product)) {
      return const SizedBox.shrink();
    }

    final cart = ref.watch(cartProvider);
    final cartIdx = cart.indexWhere(
      (item) => item.isPreorder && item.productId == widget.product.id,
    );
    final existingPreorderCartItem = cartIdx >= 0 ? cart[cartIdx] : null;
    final cartQty = existingPreorderCartItem?.quantity ?? 0;
    final effectiveQty = cartQty > 0 ? cartQty : _quantity;

    final advanceCalc = _computeAdvanceResult(effectiveQty);
    final couriersAsync = ref.watch(preorderCourierAgentsProvider);
    final courierOptions = couriersAsync.maybeWhen(
      data: (list) =>
          list.isNotEmpty ? list : PreorderService.defaultCourierAgents,
      orElse: () => PreorderService.defaultCourierAgents,
    );
    if (!courierOptions.contains(_preferredCourierAgent)) {
      _preferredCourierAgent = courierOptions.first;
    }

    final expectedDateStr =
        PreorderAdvanceValidator.formatDateYyyyMmDd(_expectedDeliveryDate);

    return Container(
      key: ValueKey('preorder_details_section_${widget.product.id}'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Heading
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pre-Order Booking Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quantity Selector (shown before booking; once booked, the bottom button turns into the [- qty +] bar)
          if (cartQty == 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quantity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primaryGreen),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('preorder_qty_decrease'),
                        constraints:
                            const BoxConstraints(minWidth: 34, minHeight: 34),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.remove,
                          size: 16,
                          color: AppColors.primaryGreen,
                        ),
                        onPressed: _quantity > 1
                            ? () {
                                setState(() {
                                  if (_paymentOption ==
                                      PreorderPaymentOption.partial) {
                                    final cur = double.tryParse(
                                            _partialAdvanceController.text
                                                .trim()) ??
                                        roundPreorderCurrency(
                                            _onlinePrice * _quantity * 0.10);
                                    final nextVal = roundPreorderCurrency(
                                        (cur / _quantity) * (_quantity - 1));
                                    _partialAdvanceController.text =
                                        nextVal.toStringAsFixed(2);
                                  }
                                  _quantity--;
                                  _formError = null;
                                });
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('preorder_qty_increase'),
                        constraints:
                            const BoxConstraints(minWidth: 34, minHeight: 34),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.add,
                          size: 16,
                          color: AppColors.primaryGreen,
                        ),
                        onPressed: _quantity < 20
                            ? () {
                                setState(() {
                                  if (_paymentOption ==
                                      PreorderPaymentOption.partial) {
                                    final cur = double.tryParse(
                                            _partialAdvanceController.text
                                                .trim()) ??
                                        roundPreorderCurrency(
                                            _onlinePrice * _quantity * 0.10);
                                    final nextVal = roundPreorderCurrency(
                                        (cur / _quantity) * (_quantity + 1));
                                    _partialAdvanceController.text =
                                        nextVal.toStringAsFixed(2);
                                  }
                                  _quantity++;
                                  _formError = null;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 22, color: AppColors.border),
          ],

          // 3.1 Booking Advance
          const Text(
            'Booking Advance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Online Price: ₹${_onlinePrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                'Product Value: ₹${advanceCalc.totalProductValue.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Full Amount vs Partial Payment Radio Buttons
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('preorder_option_full'),
                  onTap: () {
                    setState(() {
                      _paymentOption = PreorderPaymentOption.full;
                      _formError = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _paymentOption == PreorderPaymentOption.full
                          ? AppColors.primaryGreen.withValues(alpha: 0.1)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _paymentOption == PreorderPaymentOption.full
                            ? AppColors.primaryGreen
                            : AppColors.border,
                        width: _paymentOption == PreorderPaymentOption.full
                            ? 1.5
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _paymentOption == PreorderPaymentOption.full
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: _paymentOption == PreorderPaymentOption.full
                              ? AppColors.primaryGreen
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Full Amount',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  key: const ValueKey('preorder_option_partial'),
                  onTap: () {
                    setState(() {
                      _paymentOption = PreorderPaymentOption.partial;
                      _formError = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _paymentOption == PreorderPaymentOption.partial
                          ? AppColors.primaryGreen.withValues(alpha: 0.1)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _paymentOption == PreorderPaymentOption.partial
                            ? AppColors.primaryGreen
                            : AppColors.border,
                        width: _paymentOption == PreorderPaymentOption.partial
                            ? 1.5
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _paymentOption == PreorderPaymentOption.partial
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: _paymentOption == PreorderPaymentOption.partial
                              ? AppColors.primaryGreen
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Partial Payment',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_paymentOption == PreorderPaymentOption.full)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Booking Advance (Read-Only):',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${advanceCalc.bookingAdvance.toStringAsFixed(2)}',
                        key: const ValueKey('preorder_full_advance_display'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Remaining Balance:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${advanceCalc.remainingBalance.toStringAsFixed(2)}',
                        key: const ValueKey('preorder_remaining_balance_display'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('preorder_advance_input'),
                  controller: _partialAdvanceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() => _formError = null),
                  decoration: InputDecoration(
                    labelText: 'Enter Booking Advance (₹)',
                    prefixText: '₹ ',
                    helperText:
                        'Minimum permissible advance (10%): ₹${advanceCalc.minBookingAdvance.toStringAsFixed(2)} • Max (100%): ₹${advanceCalc.maxBookingAdvance.toStringAsFixed(2)}',
                    errorText: advanceCalc.errorMessage,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Remaining Balance:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '₹${advanceCalc.remainingBalance.toStringAsFixed(2)}',
                      key: const ValueKey('preorder_remaining_balance_display'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

          const Divider(height: 22, color: AppColors.border),

          // 3.2 Gift Wrap (Yes / No, default No)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Gift Wrap',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                children: [
                  ChoiceChip(
                    key: const ValueKey('preorder_gift_wrap_yes'),
                    label: const Text('Yes'),
                    selected: _giftWrap,
                    selectedColor: AppColors.primaryGreen,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _giftWrap ? Colors.white : AppColors.textPrimary,
                    ),
                    onSelected: (_) => setState(() => _giftWrap = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: const ValueKey('preorder_gift_wrap_no'),
                    label: const Text('No'),
                    selected: !_giftWrap,
                    selectedColor: AppColors.primaryGreen,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: !_giftWrap ? Colors.white : AppColors.textPrimary,
                    ),
                    onSelected: (_) => setState(() => _giftWrap = false),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3.3 Special Suggestion
          const Text(
            'Special Suggestion (Optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('preorder_special_suggestion_input'),
            controller: _specialSuggestionController,
            maxLength: 500,
            maxLines: 2,
            decoration: InputDecoration(
              hintText:
                  'Add packaging notes, gift message, or special instructions...',
              hintStyle:
                  const TextStyle(fontSize: 12, color: AppColors.textMuted),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3.4 Expected Date of Delivery (Future dates only)
          const Text(
            'Expected Date of Delivery',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('preorder_delivery_date_picker'),
            onTap: _pickExpectedDeliveryDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 17,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      expectedDateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Requested future delivery date (not a guaranteed delivery commitment).',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),

          // 3.5 Preferred Courier Agent
          const Text(
            'Preferred Courier Agent',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey('preorder_courier_dropdown_$_preferredCourierAgent'),
            initialValue: _preferredCourierAgent,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: courierOptions
                .map(
                  (agent) => DropdownMenuItem<String>(
                    value: agent,
                    child: Text(
                      agent,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _preferredCourierAgent = val);
              }
            },
          ),
          const SizedBox(height: 4),
          const Text(
            'Saved as your customer courier preference.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),

          if (_formError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Purchase / Quantity Action:
          // - Before booking (cartQty == 0): PRE-ORDER BOOKING button
          // - Once booked (cartQty > 0): [- qty +] pill bar + [🛒] View Cart button (prevents duplicate items)
          if (cartQty == 0)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                key: ValueKey('preorder_action_${widget.product.id}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _submitting ? null : _handlePreorderBooking,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.event_available_outlined, size: 18),
                label: Text(
                  _submitting ? 'PROCESSING...' : 'PRE-ORDER BOOKING',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              key: ValueKey('preorder_qty_control_${widget.product.id}'),
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const ValueKey('preorder_cart_qty_decrease'),
                          tooltip: 'Decrease quantity',
                          icon: const Icon(
                            Icons.remove,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () =>
                              _updateBookedQuantity(cartQty, cartQty - 1),
                        ),
                        Text(
                          '$cartQty',
                          key: const ValueKey('preorder_cart_qty_value'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('preorder_cart_qty_increase'),
                          tooltip: 'Increase quantity',
                          icon: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: cartQty < 20
                              ? () =>
                                  _updateBookedQuantity(cartQty, cartQty + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: OutlinedButton(
                    key: const ValueKey('preorder_view_cart_btn'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(
                        color: AppColors.primaryGreen,
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
                      context.push('/cart');
                    },
                    child: const Tooltip(
                      message: 'View cart',
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        color: AppColors.primaryGreen,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                key: const ValueKey('preorder_proceed_to_pay_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
                  context.push('/cart');
                },
                icon: const Icon(Icons.lock_outline, size: 18),
                label: Text(
                  'PROCEED TO PAY (₹${(existingPreorderCartItem?.bookingAdvance ?? advanceCalc.bookingAdvance).toStringAsFixed(2)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Conditional Pre-Order action button for compact spaces if needed.
class PreorderProductActionButton extends StatelessWidget {
  final ProductPerformance product;
  final bool compact;

  const PreorderProductActionButton({
    super.key,
    required this.product,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!PreorderService.isProductEligible(product)) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: compact ? 42 : 46,
      width: double.infinity,
      child: ElevatedButton.icon(
        key: ValueKey('preorder_action_compact_${product.id}'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.event_available_outlined, size: 18),
        label: Text(
          compact ? 'PRE-ORDER' : 'PRE-ORDER BOOKING',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: () => context
            .push('/product-detail/${Uri.encodeComponent(product.id)}'),
      ),
    );
  }
}

class PreorderStatusBadge extends StatelessWidget {
  final PreorderBookingStatus status;

  const PreorderStatusBadge({super.key, required this.status});

  Color _bgColor() {
    switch (status) {
      case PreorderBookingStatus.pendingPayment:
        return AppColors.warning.withValues(alpha: 0.14);
      case PreorderBookingStatus.confirmed:
      case PreorderBookingStatus.processing:
        return AppColors.info.withValues(alpha: 0.14);
      case PreorderBookingStatus.readyForDispatch:
      case PreorderBookingStatus.dispatched:
      case PreorderBookingStatus.delivered:
        return AppColors.success.withValues(alpha: 0.14);
      case PreorderBookingStatus.cancelled:
        return AppColors.error.withValues(alpha: 0.14);
    }
  }

  Color _fgColor() {
    switch (status) {
      case PreorderBookingStatus.pendingPayment:
        return const Color(0xFFB45309);
      case PreorderBookingStatus.confirmed:
      case PreorderBookingStatus.processing:
        return AppColors.info;
      case PreorderBookingStatus.readyForDispatch:
      case PreorderBookingStatus.dispatched:
      case PreorderBookingStatus.delivered:
        return AppColors.success;
      case PreorderBookingStatus.cancelled:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _fgColor().withValues(alpha: 0.35)),
      ),
      child: Text(
        status.displayLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _fgColor(),
        ),
      ),
    );
  }
}

class PreorderPaymentStatusBadge extends StatelessWidget {
  final PreorderPaymentStatus paymentStatus;

  const PreorderPaymentStatusBadge({super.key, required this.paymentStatus});

  Color _fgColor() {
    switch (paymentStatus) {
      case PreorderPaymentStatus.paid:
        return AppColors.success;
      case PreorderPaymentStatus.partiallyPaid:
        return AppColors.info;
      case PreorderPaymentStatus.pending:
      case PreorderPaymentStatus.unpaid:
        return const Color(0xFFB45309);
      case PreorderPaymentStatus.failed:
      case PreorderPaymentStatus.refunded:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fgColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        paymentStatus.displayLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class PreorderEligibleProductCard extends StatelessWidget {
  final PreorderEligibleProduct product;

  const PreorderEligibleProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          context.push('/product-detail/${Uri.encodeComponent(product.id)}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: AppColors.secondaryBackground
                          .withValues(alpha: 0.4),
                      padding: const EdgeInsets.all(8),
                      child: product.imageUrl != null &&
                              product.imageUrl!.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: product.imageUrl!,
                              fit: BoxFit.contain,
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
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PRE-ORDER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (product.hasDiscount)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ratingStar,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (product.packingSize.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.packingSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '₹${product.effectivePrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${product.mrp.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => context.push(
                          '/product-detail/${Uri.encodeComponent(product.id)}'),
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
                        'PRE-ORDER BOOKING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
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
