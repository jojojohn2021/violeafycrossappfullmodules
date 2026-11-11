import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/config/env_config.dart';
import '../../../../core/utils/gst_calculator.dart';
import '../../../../models/models.dart';
import '../../../../providers/app_providers.dart';
import '../../../../core/config/compliance_config.dart';
import '../../preorder/preorder_module.dart';
import '../domain/payment_orchestrator.dart';

class CheckoutData {
  final List<SalesProduct> cart;
  final CustomerAddress address;
  final double subtotal;
  final double deliveryFee;

  const CheckoutData({
    required this.cart,
    required this.address,
    required this.subtotal,
    required this.deliveryFee,
  });

  double get total => subtotal + deliveryFee;
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  late Future<List<CustomerAddress>> _addressesFuture;
  CustomerAddress? _selectedAddress;

  @override
  void initState() {
    super.initState();
    _selectedAddress = ref.read(selectedAddressProvider);
    _loadAddresses();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      }
    });
  }

  void _loadAddresses() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    _addressesFuture = user == null
        ? Future.value([])
        : ref.read(shoppingRepositoryProvider).getCustomerAddresses(user.uid);
  }

  bool _isAddingAddress = false;

  Future<void> _addAddress() async {
    if (_isAddingAddress) return;
    setState(() => _isAddingAddress = true);

    try {
      final address = await showDialog<CustomerAddress>(
        context: context,
        builder: (context) => const _AddressDialog(),
      );
      if (address == null || !mounted) return;

      final savedAddress = await ref.read(shoppingRepositoryProvider).saveCustomerAddress(address);
      if (!mounted) return;
      if (savedAddress == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save address. Please try again.')),
        );
        return;
      }
      _selectAddress(savedAddress);
      _loadAddresses();
    } finally {
      if (mounted) setState(() => _isAddingAddress = false);
    }
  }

  void _selectAddress(CustomerAddress address) {
    setState(() => _selectedAddress = address);
    ref.read(selectedAddressProvider.notifier).state = address;
  }

  Future<void> _continueToReview(List<SalesProduct> cart) async {
    final address = _selectedAddress;
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery address.')),
      );
      return;
    }

    ref.read(selectedAddressProvider.notifier).state = address;
    final hasRegularItems = cart.any((item) => !item.isPreorder);
    final res = hasRegularItems
        ? await ref.read(shoppingRepositoryProvider).getDeliveryCharge(address.pincode)
        : null;
    final deliveryFee = (hasRegularItems && res != null && res.success) ? res.deliveryCharge : 0.0;
    final summary = GstCalculator.calculateCartSummary(cart, deliveryFee: deliveryFee);

    if (!mounted) return;
    context.push(
      '/order-review',
      extra: CheckoutData(
        cart: cart,
        address: address,
        subtotal: summary.regularSalesSubtotal,
        deliveryFee: deliveryFee,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(title: const Text('Confirm Delivery Address')),
      body: cart.isEmpty
          ? const Center(child: Text('Your cart is empty.'))
          : FutureBuilder<List<CustomerAddress>>(
              future: _addressesFuture,
              builder: (context, snapshot) {
                final addresses = snapshot.data ?? [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
                }
                if (_selectedAddress == null && addresses.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedAddress == null) {
                      final chosen = addresses.firstWhere(
                        (address) => address.isDefault,
                        orElse: () => addresses.first,
                      );
                      _selectAddress(chosen);
                    }
                  });
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text('Delivery Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          if (addresses.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No saved addresses. Add one to continue.'),
                            ),
                          ...addresses.map((address) => _AddressTile(
                                address: address,
                                selected: _selectedAddress?.id == address.id,
                                onTap: () => _selectAddress(address),
                              )),
                          OutlinedButton.icon(
                            onPressed: _addAddress,
                            icon: const Icon(Icons.add),
                            label: const Text('ADD NEW ADDRESS'),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _selectedAddress == null ? null : () => _continueToReview(cart),
                            child: const Text('CONTINUE TO REVIEW'),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  final CustomerAddress address;
  final bool selected;
  final VoidCallback onTap;

  const _AddressTile({required this.address, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? AppColors.primaryGreen : AppColors.textMuted,
        ),
        title: Text(address.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${address.addressLine}\n${address.city}, ${address.district}, ${address.state} - ${address.pincode}\n${address.mobileNumber}${address.email.isNotEmpty ? ' | ${address.email}' : ''}'),
        isThreeLine: true,
      ),
    );
  }
}

class _AddressDialog extends ConsumerStatefulWidget {
  const _AddressDialog();

  @override
  ConsumerState<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends ConsumerState<_AddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _pincodeFocusNode = FocusNode();
  bool _isSaving = false;
  bool _isEmailDisabled = false;

  @override
  void initState() {
    super.initState();
    _initCustomerEmail();
  }

  Future<void> _initCustomerEmail() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final customer = await ref.read(shoppingRepositoryProvider).getCurrentCustomer();
    final existingEmail = customer?.email.trim() ?? '';
    if (mounted) {
      setState(() {
        if (existingEmail.isNotEmpty) {
          _email.text = existingEmail;
          _isEmailDisabled = true;
        } else if (user?.email != null && user!.email!.isNotEmpty) {
          _email.text = user.email!;
          _isEmailDisabled = false;
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _mobile, _email, _address, _city, _district, _state, _pincode]) {
      controller.dispose();
    }
    _pincodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _lookupPincode(String code) async {
    final cleaned = code.trim();
    if (cleaned.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 6-digit PIN code.')),
        );
      }
      _pincodeFocusNode.requestFocus();
      return;
    }

    try {
      final response = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$cleaned')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0]['Status'] == 'Success') {
          final postOffices = data[0]['PostOffice'] as List? ?? const [];
          if (postOffices.isNotEmpty) {
            final office = postOffices[0] as Map<String, dynamic>;
            final district = (office['District'] ?? office['Name'] ?? '').toString();
            final state = (office['State'] ?? '').toString();
            if (district.isNotEmpty && state.isNotEmpty) {
              setState(() {
                _district.text = district;
                _state.text = state;
              });
              return;
            }
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid pincode. Please enter a valid 6-digit PIN code.')),
        );
      }
      _pincode.clear();
      _district.clear();
      _state.clear();
      _pincodeFocusNode.requestFocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to verify pincode. Please try again.')),
        );
      }
      _pincode.clear();
      _district.clear();
      _state.clear();
      _pincodeFocusNode.requestFocus();
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    return AlertDialog(
      title: const Text('Add Delivery Address'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _field(_name, 'Customer name'),
                _field(_mobile, 'Mobile number', keyboardType: TextInputType.phone),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: _email,
                    enabled: !_isEmailDisabled,
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      final text = val?.trim() ?? '';
                      if (text.isEmpty) return 'Email address is required';
                      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                      if (!emailRegex.hasMatch(text)) return 'Enter valid email address';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: _isEmailDisabled ? 'Email address (Registered)' : 'Email address *',
                      isDense: true,
                      filled: _isEmailDisabled,
                    ),
                  ),
                ),
                _field(_address, 'Address line'),
                _field(_city, 'City'),
                TextFormField(
                  controller: _pincode,
                  focusNode: _pincodeFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onEditingComplete: () => _lookupPincode(_pincode.text),
                  onChanged: (value) {
                    if (value.trim().length == 6) {
                      _lookupPincode(value);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.trim().length != 6) {
                      return 'Enter valid 6-digit PIN code';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'PIN code', isDense: true),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _district,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'District', isDense: true, filled: true),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _state,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'State', isDense: true, filled: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _isSaving
              ? null
              : () async {
                  if (!_formKey.currentState!.validate() || user == null) return;
                  setState(() => _isSaving = true);
                  Navigator.pop(
                    context,
                    CustomerAddress(
                      id: 'addr-${DateTime.now().millisecondsSinceEpoch}',
                      userId: user.uid,
                      customerId: user.uid,
                      name: _name.text.trim(),
                      mobileNumber: _mobile.text.trim(),
                      email: _email.text.trim(),
                      addressLine: _address.text.trim(),
                      city: _city.text.trim(),
                      district: _district.text.trim(),
                      state: _state.text.trim(),
                      pincode: _pincode.text.trim(),
                      isDefault: false,
                    ),
                  );
                },
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('SAVE ADDRESS'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: _required,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}

class OrderReviewScreen extends ConsumerStatefulWidget {
  final CheckoutData data;

  const OrderReviewScreen({super.key, required this.data});

  @override
  ConsumerState<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends ConsumerState<OrderReviewScreen> {
  final _orchestrator = PaymentOrchestrator();
  bool _isStartingPayment = false;
  String _selectedPaymentMethod = 'Razorpay'; // 'Razorpay' or 'COD'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      }
    });
  }

  Future<void> _startPayment() async {
    if (_isStartingPayment) return;
    setState(() => _isStartingPayment = true);
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login?redirect=/checkout');
      return;
    }

    String customerEmail = widget.data.address.email.trim();
    if (customerEmail.isEmpty && user.email != null && user.email!.trim().isNotEmpty) {
      customerEmail = user.email!.trim();
    }
    if (customerEmail.isEmpty) {
      final customer = await ref.read(shoppingRepositoryProvider).getCurrentCustomer();
      if (customer != null && customer.email.trim().isNotEmpty) {
        customerEmail = customer.email.trim();
      }
    }

    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final isCod = _selectedPaymentMethod == 'COD' && kIsWeb;
    final hasRegularItems = widget.data.cart.any((item) => !item.isPreorder);
    final effectiveDeliveryFee = hasRegularItems ? widget.data.deliveryFee : 0.0;
    final gstSummary = GstCalculator.calculateCartSummary(
      widget.data.cart,
      deliveryFee: effectiveDeliveryFee,
    );

    final orderData = {
      'id': orderId,
      'orderNumber': orderId,
      'customerId': user.uid,
      'customerName': widget.data.address.name,
      'customerEmail': customerEmail,
      'customerMobile': sanitizeMobileNumber(widget.data.address.mobileNumber),
      'customerCompany': '',
      'products': widget.data.cart.map((item) => item.toJson()).toList(),
      'subtotal': gstSummary.regularSalesSubtotal,
      'deliveryFee': effectiveDeliveryFee,
      'regularInvoiceGrandTotal': gstSummary.regularInvoiceGrandTotal,
      'totalPreorderBookingAdvance': gstSummary.totalPreorderBookingAdvance,
      'customerGrandTotalPayable': gstSummary.customerGrandTotalPayable,
      'totalValue': gstSummary.customerGrandTotalPayable,
      'paymentStatus': isCod ? 'Pending' : 'Pending',
      'deliveryStatus': isCod ? 'Processing' : 'Pending Payment',
      'assignedTo': 'Logistics',
      'createdAt': DateTime.now().toIso8601String(),
      'paymentMethod': isCod ? 'COD' : 'UPI',
      'salesPlatform': kIsWeb ? 'webleafyearth' : 'mobleafyearth',
      'shippingAddress': widget.data.address.toJson(),
    };

    if (!mounted) return;
    try {
      if (isCod) {
        final result = await _orchestrator.payCod(orderData: orderData);
        if (!mounted) return;
        if (result.outcome == PaymentOutcome.success) {
          context.go('/payment-result?txnid=${result.transactionId}&payment_status=success');
        } else {
          context.go('/payment-result?txnid=${result.transactionId}&payment_status=failed');
        }
      } else {
        final result = await _orchestrator.pay(
          orderData: orderData,
          environment: 'Live',
          context: context,
        );

        if (!mounted) return;
        switch (result.outcome) {
          case PaymentOutcome.launchedExternally:
            break;
          case PaymentOutcome.success:
            context.go('/payment-result?txnid=${result.transactionId}&payment_status=success');
            break;
          case PaymentOutcome.cancelled:
            context.go('/payment-result?txnid=${result.transactionId}&payment_status=cancelled');
            break;
          case PaymentOutcome.failed:
          case PaymentOutcome.initFailed:
            context.go('/payment-result?txnid=${result.transactionId ?? ''}&payment_status=failed');
            break;
        }
      }
    } catch (error) {
      if (mounted) {
        final errorMsg = error.toString();
        final isRoutingError = errorMsg.contains('Configure production API routing') || errorMsg.contains('text/html');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRoutingError
                ? 'Payment API connection required. Please set the active backend server URL.'
                : 'Unable to process order: $errorMsg'),
            action: isRoutingError
                ? SnackBarAction(
                    label: 'Configure API',
                    onPressed: () => EnvConfig.showApiConfigDialog(context),
                  )
                : null,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final regularItems = data.cart.where((item) => !item.isPreorder).toList();
    final preorderItems = data.cart.where((item) => item.isPreorder).toList();
    final effectiveDeliveryFee = regularItems.isNotEmpty ? data.deliveryFee : 0.0;
    final gstSummary = GstCalculator.calculateCartSummary(
      data.cart,
      deliveryFee: effectiveDeliveryFee,
    );

    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(title: const Text('Order Review')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
            if (regularItems.isNotEmpty) ...[
              const Text('Regular Sales Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...regularItems.map((item) {
                final calc = GstCalculator.calculateItemGst(
                  price: item.price,
                  quantity: item.quantity,
                  gstPercentage: item.gstPercentage,
                  hsnCode: item.hsnCode,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                        ? CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                  ),
                  title: Text(item.productName),
                  subtitle: Text(
                    '${item.quantity} x ₹${item.price.toStringAsFixed(0)} | HSN: ${calc['hsnCode']} (GST ${calc['gstRate'].toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${(item.price * item.quantity).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('GST ₹${(calc['gstAmount'] as double).toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                );
              }),
              const Divider(height: 28),
            ],
            if (preorderItems.isNotEmpty) ...[
              const Text('PRE-ORDER BOOKING ITEMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
              const SizedBox(height: 4),
              const Text(
                'Pre-order booking advances are excluded from regular invoice GST and added to Customer Grand Total Payable.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...preorderItems.map((item) {
                final onlinePrice = item.onlinePriceSnapshot ?? item.price;
                final totalVal = item.totalProductValue ?? (onlinePrice * item.quantity);
                final advance = item.bookingAdvance ?? item.effectivePayableAmount;
                final balance = item.remainingBalance ?? (totalVal - advance);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
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
                              item.productName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Text(
                            'Advance: ₹${advance.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ref: ${item.preorderId ?? "-"} • Qty: ${item.quantity} • Online Price: ₹${onlinePrice.toStringAsFixed(2)} • Total Value: ₹${totalVal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Payment Type: ${item.paymentTypeLabel ?? "Booking Advance"} • Remaining Balance: ₹${balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Expected Delivery: ${item.expectedDeliveryDate ?? "-"} • Courier: ${item.preferredCourierAgent ?? "-"} • Gift Wrap: ${item.giftWrap == true ? "Yes" : "No"}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      if (item.specialSuggestion != null && item.specialSuggestion!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Special Suggestion: ${item.specialSuggestion}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const Divider(height: 28),
            ],
            const Text('Deliver To', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${data.address.name}\n${data.address.addressLine}\n${data.address.city}, ${data.address.district}, ${data.address.state} - ${data.address.pincode}\n${data.address.mobileNumber}${data.address.email.isNotEmpty ? ' | ${data.address.email}' : ''}'),
            const SizedBox(height: 20),
            _summaryRow('Regular Sales Subtotal', gstSummary.regularSalesSubtotal),
            _summaryRow('Regular Taxable Value (excl. GST)', gstSummary.totalTaxableValue),
            _summaryRow('GST on Regular Sales', gstSummary.totalGstAmount),
            if (regularItems.isNotEmpty) _summaryRow('Delivery Fee', effectiveDeliveryFee),
            if (gstSummary.hsnSummary.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('HSN-Wise GST Breakdown (Regular Sales)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    for (final item in gstSummary.hsnSummary)
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
            _summaryRow('REGULAR INVOICE GRAND TOTAL', gstSummary.regularInvoiceGrandTotal, bold: true),
            if (preorderItems.isNotEmpty)
              _summaryRow('Pre-Order Booking Advance', gstSummary.totalPreorderBookingAdvance),
            const Divider(height: 20),
            _summaryRow('CUSTOMER GRAND TOTAL PAYABLE', gstSummary.customerGrandTotalPayable, bold: true),
            const SizedBox(height: 20),

            // Payment Method Selection (COD is rendered EXCLUSIVELY on Web)
            const Text('Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (kIsWeb) ...[
              RadioGroup<String>(
                groupValue: _selectedPaymentMethod,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPaymentMethod = val);
                },
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: _selectedPaymentMethod == 'Razorpay' ? AppColors.primaryGreen : AppColors.border, width: _selectedPaymentMethod == 'Razorpay' ? 1.5 : 1),
                      ),
                      child: RadioListTile<String>(
                        value: 'Razorpay',
                        activeColor: AppColors.primaryGreen,
                        title: const Text('Online Payment (Cards, Net Banking, UPI)', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Secure payment processed via Razorpay'),
                        secondary: const Icon(Icons.payment, color: AppColors.primaryGreen),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: _selectedPaymentMethod == 'COD' ? AppColors.primaryGreen : AppColors.border, width: _selectedPaymentMethod == 'COD' ? 1.5 : 1),
                      ),
                      child: RadioListTile<String>(
                        value: 'COD',
                        activeColor: AppColors.primaryGreen,
                        title: const Text('Cash on Delivery (COD)', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Pay with cash when your order is delivered'),
                        secondary: const Icon(Icons.local_shipping_outlined, color: AppColors.primaryGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // On Android & iOS, COD is unavailable and hidden. Razorpay is the default payment method.
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const ListTile(
                  leading: Icon(Icons.payment, color: AppColors.primaryGreen),
                  title: Text('Online Payment (Cards, Net Banking, UPI)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Secure payment processed via Razorpay'),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Mandatory Checkout Policy Disclosure
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Policy Acknowledgement & Terms',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                      children: [
                        const TextSpan(text: 'By continuing with your order, you agree to our '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.push(ComplianceConfig.termsPath),
                            child: const Text('Terms & Conditions', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: ' and acknowledge our '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.push(ComplianceConfig.privacyPolicyPath),
                            child: const Text('Privacy', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: ', '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.push(ComplianceConfig.shippingPolicyPath),
                            child: const Text('Shipping', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: ', '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.push(ComplianceConfig.cancellationPolicyPath),
                            child: const Text('Cancellation', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: ', and '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.push(ComplianceConfig.returnRefundPolicyPath),
                            child: const Text('Return & Refund', style: TextStyle(fontSize: 11, color: AppColors.primaryGreen, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ),
                        const TextSpan(text: ' policies.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'CUSTOMER GRAND TOTAL PAYABLE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                        ),
                        Text(
                          '₹${gstSummary.customerGrandTotalPayable.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    key: const ValueKey('order_review_bottom_pay_btn'),
                    onPressed: _isStartingPayment ? null : _startPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isStartingPayment
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Icon(_selectedPaymentMethod == 'COD' ? Icons.local_shipping_outlined : Icons.lock_outline, size: 18),
                    label: Text(
                      _isStartingPayment
                          ? (_selectedPaymentMethod == 'COD' ? 'PLACING...' : 'STARTING...')
                          : (_selectedPaymentMethod == 'COD' ? 'CONFIRM COD ORDER' : 'PAY NOW'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 17 : 14);
    final isFreeDelivery = label == 'Delivery Fee' && value == 0;
    final valueText = isFreeDelivery ? 'Free Delivery (₹0)' : '₹${value.toStringAsFixed(2)}';
    final valueStyle = isFreeDelivery ? style.copyWith(color: AppColors.primaryGreen, fontWeight: FontWeight.bold) : style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(valueText, style: valueStyle),
        ],
      ),
    );
  }
}

class PaymentResultScreen extends ConsumerStatefulWidget {
  final String transactionId;
  final String status;

  const PaymentResultScreen({super.key, required this.transactionId, required this.status});

  @override
  ConsumerState<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends ConsumerState<PaymentResultScreen> {
  String? _verifiedStatus;
  bool _cartCleared = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentStatus();
  }

  Future<void> _loadPaymentStatus() async {
    if (widget.transactionId.isEmpty) {
      if (mounted) setState(() => _verifiedStatus = 'Failed');
      return;
    }
    try {
      final repo = ref.read(shoppingRepositoryProvider);
      final response = await repo.getPaymentStatus(widget.transactionId);
      if (!mounted) return;

      final fetchedStatus = response?['status']?.toString() ?? (widget.status.toLowerCase() == 'success' ? 'Success' : 'Failed');
      final rawStatus = response?['rawStatus']?.toString() ?? fetchedStatus;
      final pm = (response?['paymentMethod'] ?? response?['orderPayload']?['paymentMethod'])?.toString().toUpperCase() ?? '';

      final isCod = pm == 'COD' || response?['paymentGateway'] == 'COD';
      final isCodPending = isCod && (rawStatus == 'PENDING' || rawStatus == 'Pending' || fetchedStatus == 'PENDING' || fetchedStatus == 'Pending');
      final isSuccess = fetchedStatus == 'Success' ||
          fetchedStatus == 'Paid' ||
          fetchedStatus == 'PAYMENT_SUCCESS' ||
          isCodPending ||
          (response == null && widget.status.toLowerCase() == 'success');

      setState(() => _verifiedStatus = isSuccess ? 'Success' : fetchedStatus);
      if (isSuccess && !_cartCleared) {
        ref.read(cartProvider.notifier).clearCart();
        ref.invalidate(salesOrdersProvider);
        ref.invalidate(myPreordersProvider);
        setState(() => _cartCleared = true);
        // Brief confirmation, then land on the same My Orders screen a successful checkout leads to.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) context.go('/orders');
        });
      }
    } catch (e) {
      debugPrint('[PaymentResultScreen] Error fetching payment status: $e');
      if (mounted) {
        if (widget.status.toLowerCase() == 'success') {
          ref.read(cartProvider.notifier).clearCart();
          ref.invalidate(salesOrdersProvider);
          ref.invalidate(myPreordersProvider);
          setState(() {
            _verifiedStatus = 'Success';
            _cartCleared = true;
          });
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) context.go('/orders');
          });
        } else {
          setState(() => _verifiedStatus = 'Failed');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = _verifiedStatus == 'Success';
    final waiting = _verifiedStatus == null;
    final cancelled = widget.status == 'cancelled';
    return Scaffold(
      appBar: AppBar(title: Text(waiting ? 'Confirming Order' : success ? 'Order Confirmed' : 'Payment ${cancelled ? 'Cancelled' : 'Failed'}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (waiting)
                const CircularProgressIndicator(color: AppColors.primaryGreen)
              else
                Icon(success ? Icons.check_circle_outline : Icons.error_outline, size: 72, color: success ? AppColors.primaryGreen : AppColors.error),
              const SizedBox(height: 16),
              Text(
                waiting
                    ? 'Verifying your order with the server...'
                    : success
                        ? 'Order confirmed successfully.'
                        : 'Order was not completed. Your cart has not been cleared.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (widget.transactionId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Order ID: ${widget.transactionId}', style: const TextStyle(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 24),
              if (!waiting) ...[
                ElevatedButton(onPressed: () => context.go(success ? '/orders' : '/checkout'), child: Text(success ? 'VIEW ORDER HISTORY' : 'RETRY PAYMENT')),
                if (!success) TextButton(onPressed: () => context.go('/cart'), child: const Text('RETURN TO CART')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
