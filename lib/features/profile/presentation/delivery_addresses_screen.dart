import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../providers/app_providers.dart';

class DeliveryAddressesScreen extends ConsumerStatefulWidget {
  const DeliveryAddressesScreen({super.key});

  @override
  ConsumerState<DeliveryAddressesScreen> createState() => _DeliveryAddressesScreenState();
}

class _DeliveryAddressesScreenState extends ConsumerState<DeliveryAddressesScreen> {
  late Future<List<CustomerDeliveryAddress>> _addressesFuture;
  late Future<CustomerPerformance?> _customerFuture;
  bool _isActionLoading = false;

  // Permanent Address form controllers & nodes
  final _permFormKey = GlobalKey<FormState>();
  final _permNameController = TextEditingController();
  final _permMobileController = TextEditingController();
  final _permCompanyController = TextEditingController();
  final _permEmailController = TextEditingController();
  final _permPincodeController = TextEditingController();
  final _permStateController = TextEditingController();
  final _permDistrictController = TextEditingController();
  final _permAddressController = TextEditingController();
  final _permPincodeFocusNode = FocusNode();

  bool _isPermPincodeLoading = false;
  String? _permPincodeErrorText;
  bool _isPermUpdating = false;
  bool _isPermFormPopulated = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadCustomerProfile();
  }

  @override
  void dispose() {
    _permNameController.dispose();
    _permMobileController.dispose();
    _permCompanyController.dispose();
    _permEmailController.dispose();
    _permPincodeController.dispose();
    _permStateController.dispose();
    _permDistrictController.dispose();
    _permAddressController.dispose();
    _permPincodeFocusNode.dispose();
    super.dispose();
  }

  void _loadAddresses() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userKey = user?.uid ?? user?.phoneNumber ?? '';
    setState(() {
      _addressesFuture = userKey.isEmpty
          ? Future.value([])
          : ref.read(shoppingRepositoryProvider).getCustomerAddresses(userKey);
    });
  }

  void _loadCustomerProfile() {
    setState(() {
      _isPermFormPopulated = false;
      _customerFuture = ref.read(shoppingRepositoryProvider).getCurrentCustomer();
    });
  }

  void _populatePermanentAddressForm(CustomerPerformance? customer) {
    if (_isPermFormPopulated && !_isPermUpdating) return;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userPhone = user?.phoneNumber ?? '';

    final rawMobile = (customer?.mobilenumberwithcountrycode != null && customer!.mobilenumberwithcountrycode.isNotEmpty)
        ? customer.mobilenumberwithcountrycode
        : ((customer?.mobileNumber != null && customer!.mobileNumber.isNotEmpty) ? customer.mobileNumber : userPhone);

    _permNameController.text = customer?.name ?? (user?.displayName ?? '');
    _permMobileController.text = rawMobile;
    _permCompanyController.text = customer?.company ?? '';
    _permEmailController.text = (customer?.email != null && customer!.email.isNotEmpty) ? customer.email : (user?.email ?? '');
    _permPincodeController.text = customer?.pincode ?? '';
    _permStateController.text = customer?.state ?? '';
    _permDistrictController.text = customer?.district ?? '';
    _permAddressController.text = customer?.address ?? '';
    _isPermFormPopulated = true;
  }

  Future<void> _performPermPincodeLookup(String code) async {
    final cleanedPincode = code.trim();
    if (cleanedPincode.length != 6 || !RegExp(r'^\d{6}$').hasMatch(cleanedPincode)) {
      setState(() {
        _permPincodeErrorText = 'Not a valid pincode (exactly 6 digits required)';
        _permStateController.clear();
        _permDistrictController.clear();
      });
      return;
    }

    setState(() {
      _isPermPincodeLoading = true;
      _permPincodeErrorText = null;
    });

    try {
      final result = await ref.read(shoppingRepositoryProvider).lookupPincode(cleanedPincode);
      if (result != null) {
        setState(() {
          _permStateController.text = result.state;
          _permDistrictController.text = result.district;
          _permPincodeErrorText = null;
          _isPermPincodeLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[PermPincodeLookup] Error: $e');
    }

    setState(() {
      _isPermPincodeLoading = false;
      _permPincodeErrorText = 'Not a valid pincode or location could not be resolved';
      _permStateController.clear();
      _permDistrictController.clear();
    });
  }

  Future<void> _submitPermanentAddressUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    final pincode = _permPincodeController.text.trim();

    if (pincode.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pincode)) {
      await _performPermPincodeLookup(pincode);
    }

    if (!(_permFormKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_permStateController.text.trim().isEmpty || _permDistrictController.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Valid 6-digit pincode is required to resolve State and District')),
      );
      return;
    }

    setState(() => _isPermUpdating = true);

    try {
      final updatedCustomer = await ref.read(shoppingRepositoryProvider).updatePermanentAddress(
        name: _permNameController.text.trim(),
        company: _permCompanyController.text.trim(),
        email: _permEmailController.text.trim(),
        address: _permAddressController.text.trim(),
        pincode: pincode,
      );

      if (updatedCustomer != null && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permanent Address updated successfully!')),
        );
        _populatePermanentAddressForm(updatedCustomer);
        setState(() {
          _customerFuture = Future.value(updatedCustomer);
        });
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to update Permanent Address')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error updating Permanent Address: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPermUpdating = false);
      }
    }
  }

  Future<void> _setDefaultAddress(CustomerDeliveryAddress address) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userKey = user?.uid ?? user?.phoneNumber ?? '';
    if (userKey.isEmpty || address.isDefault) return;

    setState(() => _isActionLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await ref
          .read(shoppingRepositoryProvider)
          .setDefaultCustomerAddress(address.id, userKey);
      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Default delivery address updated!')),
        );
        _loadAddresses();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update default address: $e')),
      );
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _deleteAddress(CustomerDeliveryAddress address) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to remove this delivery address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionLoading = true);
    try {
      final success = await ref
          .read(shoppingRepositoryProvider)
          .deleteCustomerAddress(address.id);
      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Delivery address removed')),
        );
        _loadAddresses();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete address: $e')),
      );
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _openAddAddressDialog([List<CustomerDeliveryAddress> existing = const []]) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userKey = user?.uid ?? user?.phoneNumber ?? '';

    // Fetch customer profile to check if email already exists in customers table
    final customer = await ref.read(shoppingRepositoryProvider).getCurrentCustomer();
    if (!mounted) return;
    final existingCustomerEmail = customer?.email.trim() ?? '';
    final bool isEmailDisabled = existingCustomerEmail.isNotEmpty;

    final nameController = TextEditingController(text: user?.displayName ?? '');
    final rawMobileDigits = (user?.phoneNumber ?? '')
        .replaceAll('+91', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .trim();
    final contactMobileController = TextEditingController(
      text: rawMobileDigits.length == 10 ? rawMobileDigits : '',
    );
    final emailController = TextEditingController(
      text: existingCustomerEmail.isNotEmpty ? existingCustomerEmail : (user?.email ?? ''),
    );
    final addressLineController = TextEditingController();
    final cityController = TextEditingController();
    final stateController = TextEditingController();
    final pincodeController = TextEditingController();
    final pincodeFocusNode = FocusNode();

    bool setAsDefault = existing.isEmpty;
    bool isPincodeLoading = false;
    String? pincodeErrorText;

    final formKey = GlobalKey<FormState>();

    final newAddress = await showModalBottomSheet<CustomerDeliveryAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> performPincodeLookup(String code) async {
            final cleanedPincode = code.trim();
            if (cleanedPincode.length != 6) {
              setModalState(() {
                pincodeErrorText = 'Not a valid pincode (6 digits required)';
                cityController.clear();
                stateController.clear();
              });
              pincodeFocusNode.requestFocus();
              return;
            }

            setModalState(() {
              isPincodeLoading = true;
              pincodeErrorText = null;
            });

            try {
              final url = Uri.parse('https://api.postalpincode.in/pincode/$cleanedPincode');
              final response = await http.get(url).timeout(const Duration(seconds: 4));
              if (response.statusCode == 200) {
                final List data = jsonDecode(response.body);
                if (data.isNotEmpty && data[0]['Status'] == 'Success') {
                  final postOffices = data[0]['PostOffice'] as List;
                  if (postOffices.isNotEmpty) {
                    final district = postOffices[0]['District'] ?? postOffices[0]['Name'] ?? '';
                    final state = postOffices[0]['State'] ?? '';
                    setModalState(() {
                      cityController.text = district;
                      stateController.text = state;
                      pincodeErrorText = null;
                      isPincodeLoading = false;
                    });
                    return;
                  }
                }
              }
            } catch (e) {
              debugPrint('[PincodeLookup] Error: $e');
            }

            setModalState(() {
              isPincodeLoading = false;
              pincodeErrorText = 'Not a valid pincode';
              cityController.clear();
              stateController.clear();
            });
            pincodeFocusNode.requestFocus();
          }

          return Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Delivery Address',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 1. Full Name
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // 2. Contact Mobile No (Non-editable +91 prefix, exactly 10 digits)
                    TextFormField(
                      controller: contactMobileController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Contact Mobile No *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '+91 ',
                        prefixStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      validator: (val) => val == null || val.trim().length != 10 ? 'Enter valid 10-digit mobile number' : null,
                    ),
                    const SizedBox(height: 12),

                    // 3. Email Address (Positioned below Mobile No)
                    TextFormField(
                      controller: emailController,
                      enabled: !isEmailDisabled,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: isEmailDisabled ? 'Email Address (Registered)' : 'Email Address *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: isEmailDisabled,
                      ),
                      validator: (val) {
                        final text = val?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Email address is required';
                        }
                        final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                        if (!emailRegex.hasMatch(text)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // 4. House / Building / Street Address
                    TextFormField(
                      controller: addressLineController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'House / Building / Street Address *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Address is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // 5. City
                    TextFormField(
                      controller: cityController,
                      decoration: const InputDecoration(
                        labelText: 'City *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'City is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // 6. Pincode (6 digits, positioned AFTER City)
                    Focus(
                      onFocusChange: (hasFocus) {
                        if (!hasFocus && pincodeController.text.trim().isNotEmpty) {
                          performPincodeLookup(pincodeController.text.trim());
                        }
                      },
                      child: TextFormField(
                        controller: pincodeController,
                        focusNode: pincodeFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Pincode (6 digits) *',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.pin_drop_outlined),
                          errorText: pincodeErrorText,
                          suffixIcon: isPincodeLoading
                              ? const UnconstrainedBox(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                                  ),
                                )
                              : null,
                        ),
                        onFieldSubmitted: (_) => performPincodeLookup(pincodeController.text.trim()),
                        onChanged: (val) {
                          if (val.trim().length == 6) {
                            performPincodeLookup(val);
                          } else if (pincodeErrorText != null) {
                            setModalState(() => pincodeErrorText = null);
                          }
                        },
                        validator: (val) {
                          if (val == null || val.trim().length != 6) {
                            return 'Enter valid 6-digit pincode';
                          }
                          if (pincodeErrorText != null) {
                            return pincodeErrorText;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 7. District (Read-only / Non-editable)
                    TextFormField(
                      controller: cityController,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'District (Auto-filled)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city_outlined),
                        filled: true,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Enter a valid pincode to fill District' : null,
                    ),
                    const SizedBox(height: 12),

                    // 8. State (Read-only / Non-editable)
                    TextFormField(
                      controller: stateController,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'State (Auto-filled)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.map_outlined),
                        filled: true,
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Enter a valid pincode to fill State' : null,
                    ),
                    const SizedBox(height: 12),

                    // 9. Set as Default Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Set as default delivery address',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      activeThumbColor: AppColors.primaryGreen,
                      value: setAsDefault,
                      onChanged: (val) => setModalState(() => setAsDefault = val),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          if (pincodeController.text.trim().length != 6) {
                            performPincodeLookup(pincodeController.text);
                            return;
                          }
                          if (formKey.currentState!.validate()) {
                            final rawDigits = contactMobileController.text.trim();
                            final fullMobile = rawDigits.startsWith('+91') ? rawDigits : '+91 $rawDigits';
                            final district = cityController.text.trim();
                            final addr = CustomerDeliveryAddress(
                              id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
                              userId: userKey,
                              customerId: userKey,
                              name: nameController.text.trim(),
                              mobileNumber: fullMobile,
                              email: emailController.text.trim(),
                              addressLine: addressLineController.text.trim(),
                              city: cityController.text.trim(),
                              district: district,
                              state: stateController.text.trim(),
                              pincode: pincodeController.text.trim(),
                              isDefault: setAsDefault,
                            );
                            Navigator.of(ctx).pop(addr);
                          }
                        },
                        child: const Text(
                          'Save Delivery Address',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    pincodeFocusNode.dispose();

    if (newAddress != null) {
      setState(() => _isActionLoading = true);
      try {
        final saved = await ref.read(shoppingRepositoryProvider).saveCustomerAddress(newAddress);
        if (saved != null) {
          if (newAddress.isDefault) {
            await ref.read(shoppingRepositoryProvider).setDefaultCustomerAddress(saved.id, userKey);
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Delivery address saved successfully!')),
          );
          _loadAddresses();
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to save address: $e')),
        );
      } finally {
        if (mounted) setState(() => _isActionLoading = false);
      }
    }
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('CUSTOMER FULL NAME *:'),
        TextFormField(
          controller: _permNameController,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Johnathan Doe',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: (val) => val == null || val.trim().isEmpty ? 'Customer full name is required' : null,
        ),
      ],
    );
  }

  Widget _buildMobileField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('MOBILE NUMBER * (UNIQUE KEY):'),
        TextFormField(
          controller: _permMobileController,
          enabled: false,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. +91 9876543210',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('COMPANY BRANCH / STORE NAME:'),
        TextFormField(
          controller: _permCompanyController,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Acme Retailers (Optional)',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('CORPORATE EMAIL ADDRESS:'),
        TextFormField(
          controller: _permEmailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. jdoe@acme.com',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildPincodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('PIN CODE:'),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus && _permPincodeController.text.trim().isNotEmpty) {
              _performPermPincodeLookup(_permPincodeController.text.trim());
            }
          },
          child: TextFormField(
            controller: _permPincodeController,
            focusNode: _permPincodeFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. 682011',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              errorText: _permPincodeErrorText,
              suffixIcon: _isPermPincodeLoading
                  ? const UnconstrainedBox(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                      ),
                    )
                  : null,
            ),
            onFieldSubmitted: (_) => _performPermPincodeLookup(_permPincodeController.text.trim()),
            onChanged: (val) {
              if (val.trim().length == 6) {
                _performPermPincodeLookup(val);
              } else if (_permPincodeErrorText != null) {
                setState(() => _permPincodeErrorText = null);
              }
            },
            validator: (val) {
              if (val == null || val.trim().length != 6 || !RegExp(r'^\d{6}$').hasMatch(val.trim())) {
                return 'Enter valid 6-digit pincode';
              }
              if (_permPincodeErrorText != null) {
                return _permPincodeErrorText;
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('STATE REGION:'),
        TextFormField(
          controller: _permStateController,
          enabled: false,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: '-- Search & Select State --',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: (val) => val == null || val.trim().isEmpty ? 'State is auto-populated from pincode' : null,
        ),
      ],
    );
  }

  Widget _buildDistrictField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('DISTRICT:'),
        TextFormField(
          controller: _permDistrictController,
          enabled: false,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Select State First',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: (val) => val == null || val.trim().isEmpty ? 'District is auto-populated from pincode' : null,
        ),
      ],
    );
  }

  Widget _buildAddressField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('FULL GEOGRAPHIC ADDRESS DESTINATION:'),
        TextFormField(
          controller: _permAddressController,
          maxLines: 2,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Door No. 45-B, MG Road, opposite Grand Mall',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: (val) => val == null || val.trim().isEmpty ? 'Full address destination is required' : null,
        ),
      ],
    );
  }

  Widget _buildPermanentAddressCard(CustomerPerformance? customer) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _permFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home_work_outlined, color: AppColors.primaryGreen, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERMANENT ADDRESS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Customer primary record & destination',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 700;
                if (isWide) {
                  return Column(
                    children: [
                      // Row 1: Name, Mobile, Company
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildNameField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMobileField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildCompanyField()),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Row 2: Email, Pincode, State
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildEmailField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPincodeField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildStateField()),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Row 3: District, Full Address
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 1, child: _buildDistrictField()),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: _buildAddressField()),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildNameField(),
                      const SizedBox(height: 12),
                      _buildMobileField(),
                      const SizedBox(height: 12),
                      _buildCompanyField(),
                      const SizedBox(height: 12),
                      _buildEmailField(),
                      const SizedBox(height: 12),
                      _buildPincodeField(),
                      const SizedBox(height: 12),
                      _buildStateField(),
                      const SizedBox(height: 12),
                      _buildDistrictField(),
                      const SizedBox(height: 12),
                      _buildAddressField(),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 1,
                ),
                onPressed: _isPermUpdating ? null : _submitPermanentAddressUpdate,
                icon: _isPermUpdating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, color: Colors.white),
                label: Text(
                  _isPermUpdating ? 'Updating...' : 'Update',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: const Text('Delivery Addresses'),
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              _loadAddresses();
              _loadCustomerProfile();
            },
            color: AppColors.primaryGreen,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- TOP SECTION: Permanent Address Card ---
                  FutureBuilder<CustomerPerformance?>(
                    future: _customerFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !_isPermFormPopulated) {
                        return Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(color: AppColors.primaryGreen),
                          ),
                        );
                      }

                      final customer = snapshot.data;
                      _populatePermanentAddressForm(customer);

                      return _buildPermanentAddressCard(customer);
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'OTHER DELIVERY LOCATIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),

                  // --- LOWER SECTION: Additional Delivery Addresses List ---
                  FutureBuilder<List<CustomerDeliveryAddress>>(
                    future: _addressesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: CircularProgressIndicator(color: AppColors.primaryGreen),
                          ),
                        );
                      }

                      final addresses = snapshot.data ?? [];

                      if (addresses.isEmpty) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_off_outlined,
                                  size: 36,
                                  color: AppColors.primaryGreen.withValues(alpha: 0.7),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No Additional Delivery Addresses',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Add your office, secondary home or branch locations below.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryGreen,
                                    side: const BorderSide(color: AppColors.primaryGreen),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => _openAddAddressDialog(addresses),
                                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                                  label: const Text('Add Location', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: addresses.length,
                        itemBuilder: (context, index) {
                          final address = addresses[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: address.isDefault ? AppColors.primaryGreen : AppColors.border,
                                width: address.isDefault ? 1.5 : 1,
                              ),
                              boxShadow: [
                                if (address.isDefault)
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            address.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          if (address.isDefault) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primaryGreen.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: AppColors.primaryGreen, width: 0.8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle, size: 12, color: AppColors.primaryGreen),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'DEFAULT',
                                                    style: TextStyle(
                                                      color: AppColors.primaryGreen,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                        tooltip: 'Delete Address',
                                        onPressed: () => _deleteAddress(address),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    address.mobileNumber,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                  if (address.email.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      address.email.trim(),
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    '${address.addressLine}, ${address.district}, ${address.state} - ${address.pincode}',
                                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.3),
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (!address.isDefault)
                                        TextButton.icon(
                                          onPressed: () => _setDefaultAddress(address),
                                          icon: const Icon(Icons.radio_button_unchecked, size: 16, color: AppColors.primaryGreen),
                                          label: const Text(
                                            'Set as Default',
                                            style: TextStyle(color: AppColors.primaryGreen, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      else
                                        const Row(
                                          children: [
                                            Icon(Icons.radio_button_checked, size: 16, color: AppColors.primaryGreen),
                                            SizedBox(width: 4),
                                            Text(
                                              'Default Address',
                                              style: TextStyle(color: AppColors.primaryGreen, fontSize: 12, fontWeight: FontWeight.bold),
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

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          if (_isActionLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final currentAddresses = await _addressesFuture;
          if (!mounted) return;
          _openAddAddressDialog(currentAddresses);
        },
        backgroundColor: AppColors.primaryGreen,
        icon: const Icon(Icons.add_location_alt_outlined, color: Colors.white),
        label: const Text('Add Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
