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
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  void _loadAddresses() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userKey = user?.phoneNumber ?? user?.uid ?? '';
    setState(() {
      _addressesFuture = userKey.isEmpty
          ? Future.value([])
          : ref.read(shoppingRepositoryProvider).getCustomerAddresses(userKey);
    });
  }

  Future<void> _setDefaultAddress(CustomerDeliveryAddress address) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final userKey = user?.phoneNumber ?? user?.uid ?? '';
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
    final userKey = user?.phoneNumber ?? user?.uid ?? '';
    final primaryMobileNumber = user?.phoneNumber ?? user?.email ?? 'Not Available';

    final nameController = TextEditingController(text: user?.displayName ?? '');
    final rawMobileDigits = (user?.phoneNumber ?? '')
        .replaceAll('+91', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .trim();
    final contactMobileController = TextEditingController(
      text: rawMobileDigits.length == 10 ? rawMobileDigits : '',
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
                    const Divider(height: 20),

                    // 1. Primary Mobile (Disabled)
                    TextFormField(
                      initialValue: primaryMobileNumber,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Primary Mobile',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_locked_outlined),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Recipient Name
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Recipient Name is required' : null,
                    ),
                    const SizedBox(height: 12),

                    // 3. Contact Mobile No (Non-editable +91 prefix, exactly 10 digits)
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

                    // 8. Set as Default Switch
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
          FutureBuilder<List<CustomerDeliveryAddress>>(
            future: _addressesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryGreen),
                );
              }

              final addresses = snapshot.data ?? [];

              if (addresses.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_off_outlined,
                            size: 48,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Delivery Addresses Saved',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add your home, office or delivery location to order faster.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _openAddAddressDialog(addresses),
                          icon: const Icon(Icons.add_location_alt_outlined, color: Colors.white),
                          label: const Text(
                            'Add New Address',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _loadAddresses(),
                color: AppColors.primaryGreen,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
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
                ),
              );
            },
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
