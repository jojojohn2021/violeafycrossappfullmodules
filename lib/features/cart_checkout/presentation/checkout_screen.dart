import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/app_colors.dart';
import '../../../../models/models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../providers/app_providers.dart';
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
    _loadAddresses();
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
      setState(() {
        _selectedAddress = savedAddress;
        _loadAddresses();
      });
    } finally {
      if (mounted) setState(() => _isAddingAddress = false);
    }
  }

  void _continueToReview(List<SalesProduct> cart) {
    final address = _selectedAddress;
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery address.')),
      );
      return;
    }
    final subtotal = cart.fold<double>(0, (sum, item) => sum + item.price * item.quantity);
    context.push(
      '/order-review',
      extra: CheckoutData(
        cart: cart,
        address: address,
        subtotal: subtotal,
        deliveryFee: 30,
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
                  // Use a post-frame callback to avoid side-effects during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedAddress == null) {
                      setState(() {
                        _selectedAddress = addresses.firstWhere(
                          (address) => address.isDefault,
                          orElse: () => addresses.first,
                        );
                      });
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
                                onTap: () => setState(() => _selectedAddress = address),
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
    final orderData = {
      'id': orderId,
      'orderNumber': orderId,
      'customerId': user.uid,
      'customerName': widget.data.address.name,
      'customerEmail': customerEmail,
      'customerMobile': widget.data.address.mobileNumber,
      'customerCompany': '',
      'products': widget.data.cart.map((item) => item.toJson()).toList(),
      'totalValue': widget.data.total,
      'paymentStatus': 'Pending',
      'deliveryStatus': 'Pending Payment',
      'assignedTo': 'Logistics',
      'createdAt': DateTime.now().toIso8601String(),
      'paymentMethod': 'UPI',
      'shippingAddress': widget.data.address.toJson(),
    };

    final payuEnv = ref.read(payuEnvironmentProvider);
    final payuEnabled = ref.read(payuEnabledProvider);

    if (!mounted) return;
    try {
      final result = await _orchestrator.pay(
        orderData: orderData,
        environment: payuEnv,
        context: context,
        payuEnabled: payuEnabled,
      );

      if (!mounted) return;
      switch (result.outcome) {
        case PaymentOutcome.launchedExternally:
          // Web Redirect opened in the external browser; PayU's callback will
          // bring the user back into the existing /payment-result route.
          break;
        case PaymentOutcome.success:
          context.push('/payment-result?txnid=${result.transactionId}&payment_status=success');
          break;
        case PaymentOutcome.cancelled:
          context.push('/payment-result?txnid=${result.transactionId}&payment_status=cancelled');
          break;
        case PaymentOutcome.failed:
        case PaymentOutcome.initFailed:
          context.push('/payment-result?txnid=${result.transactionId ?? ''}&payment_status=failed');
          break;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to start payment: $error')));
      }
    } finally {
      if (mounted) setState(() => _isStartingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(title: const Text('Order Review')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...data.cart.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                      ? CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover)
                      : const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                ),
                title: Text(item.productName),
                subtitle: Text('${item.quantity} x ₹${item.price.toStringAsFixed(0)}'),
                trailing: Text('₹${(item.price * item.quantity).toStringAsFixed(0)}'),
              )),
          const Divider(height: 28),
          const Text('Deliver To', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('${data.address.name}\n${data.address.addressLine}\n${data.address.city}, ${data.address.district}, ${data.address.state} - ${data.address.pincode}\n${data.address.mobileNumber}${data.address.email.isNotEmpty ? ' | ${data.address.email}' : ''}'),
          const SizedBox(height: 20),
          _summaryRow('Subtotal', data.subtotal),
          _summaryRow('Delivery Fee', data.deliveryFee),
          const Divider(),
          _summaryRow('Grand Total', data.total, bold: true),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isStartingPayment ? null : _startPayment,
            icon: _isStartingPayment ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.lock_outline),
            label: Text(_isStartingPayment ? 'STARTING PAYMENT...' : 'PAY NOW'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 17 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text('₹${value.toStringAsFixed(0)}', style: style)]),
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
  final _apiClient = ApiClient();
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
      final response = await _apiClient.get('/api/payment/status/${widget.transactionId}');
      if (!mounted) return;
      setState(() => _verifiedStatus = response['status']?.toString() ?? 'Failed');
      if (_verifiedStatus == 'Success' && !_cartCleared) {
        ref.read(cartProvider.notifier).clearCart();
        setState(() => _cartCleared = true);
        // Brief confirmation, then land on the same My Orders screen a successful checkout leads to.
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) context.go('/orders');
        });
      }
    } catch (_) {
      if (mounted) setState(() => _verifiedStatus = 'Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = _verifiedStatus == 'Success';
    final waiting = _verifiedStatus == null;
    final cancelled = widget.status == 'cancelled';
    return Scaffold(
      appBar: AppBar(title: Text(waiting ? 'Checking Payment' : success ? 'Order Confirmed' : 'Payment ${cancelled ? 'Cancelled' : 'Failed'}')),
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
              Text(waiting ? 'Verifying your payment with the server...' : success ? 'Payment verified and order confirmed.' : 'Payment was not completed. Your cart has not been cleared.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (widget.transactionId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Transaction: ${widget.transactionId}', style: const TextStyle(color: AppColors.textSecondary)),
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
