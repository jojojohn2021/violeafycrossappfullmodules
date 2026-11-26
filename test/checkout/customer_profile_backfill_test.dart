import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/models/models.dart';
import 'package:leafy_webapp/repositories/shopping_repository.dart';

CustomerPerformance _makeCustomer({
  String name = '',
  String email = '',
  String address = '',
  String district = '',
  String state = '',
  String? pincode,
}) {
  return CustomerPerformance(
    id: 'cust_1',
    authUid: 'uid_1',
    name: name,
    company: '',
    email: email,
    mobileNumber: '9876543210',
    address: address,
    state: state,
    district: district,
    pincode: pincode,
    totalSpent: 0,
    dealsClosed: 0,
    satisfactionScore: 0,
    lastOrderDate: '2026-11-25',
    tier: 'Bronze',
  );
}

CustomerDeliveryAddress _makeAddress({
  String name = 'Ananya Nair',
  String email = 'ananya@example.com',
  String addressLine = '12 MG Road',
  String city = 'Kochi',
  String district = 'Ernakulam',
  String state = 'Kerala',
  String pincode = '682016',
}) {
  return CustomerDeliveryAddress(
    id: 'addr_1',
    userId: 'uid_1',
    customerId: 'uid_1',
    name: name,
    mobileNumber: '9876543210',
    email: email,
    addressLine: addressLine,
    city: city,
    district: district,
    state: state,
    pincode: pincode,
    isDefault: true,
  );
}

void main() {
  group('ShoppingRepository customer profile backfill from delivery address', () {
    test('formatCustomerAddressLine combines addressLine and city without duplicating city', () {
      expect(
        ShoppingRepository.formatCustomerAddressLine(_makeAddress(addressLine: '12 MG Road', city: 'Kochi')),
        '12 MG Road, Kochi',
      );
      expect(
        ShoppingRepository.formatCustomerAddressLine(_makeAddress(addressLine: '12 MG Road, Kochi', city: 'Kochi')),
        '12 MG Road, Kochi',
      );
      expect(
        ShoppingRepository.formatCustomerAddressLine(_makeAddress(addressLine: '  ', city: 'Kochi')),
        'Kochi',
      );
    });

    test('fills all blank/missing fields on organic signup customer', () {
      final blankCustomer = _makeCustomer();
      final address = _makeAddress();

      final updates = ShoppingRepository.buildMissingCustomerProfileUpdates(blankCustomer, address);

      expect(updates, {
        'name': 'Ananya Nair',
        'email': 'ananya@example.com',
        'address': '12 MG Road, Kochi',
        'district': 'Ernakulam',
        'state': 'Kerala',
        'pincode': '682016',
      });
    });

    test('preserves existing non-empty customer fields and only backfills missing ones', () {
      final existingCustomer = _makeCustomer(
        name: 'Existing Name',
        email: 'existing@example.com',
        address: 'Existing Permanent Address',
        district: '',
        state: 'Kerala',
        pincode: '',
      );
      final giftAddress = _makeAddress(
        name: 'Gift Recipient',
        email: 'gift@example.com',
        addressLine: '99 Gift Street',
        city: 'Thrissur',
        district: 'Thrissur',
        state: 'Tamil Nadu',
        pincode: '680001',
      );

      final updates = ShoppingRepository.buildMissingCustomerProfileUpdates(existingCustomer, giftAddress);

      expect(updates, {
        'district': 'Thrissur',
        'pincode': '680001',
      });
    });

    test('skips invalid email and returns empty map when customer already has all fields', () {
      final blankEmailCustomer = _makeCustomer(
        name: 'Ananya',
        email: '',
        address: '12 MG Road',
        district: 'Ernakulam',
        state: 'Kerala',
        pincode: '682016',
      );
      final invalidEmailAddress = _makeAddress(email: 'not-an-email');

      final updates = ShoppingRepository.buildMissingCustomerProfileUpdates(blankEmailCustomer, invalidEmailAddress);
      expect(updates, isEmpty);
    });
  });
}
