import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/models/models.dart';
import 'package:leafy_webapp/repositories/shopping_repository.dart';

void main() {
  group('Referral & Partner Commission Display Models', () {
    test('CommissionSummary parses server earnings endpoint payload', () {
      final json = {
        'commissionEarned': 1250.50,
        'commissionPayable': 450.00,
        'commissionPaid': 800.00,
        'pending': 150.00,
        'confirmed': 1100.00,
      };

      final summary = CommissionSummary.fromJson(json);

      expect(summary.pending, 150.00);
      expect(summary.confirmed, 1100.00);
      expect(summary.payable, 450.00);
      expect(summary.paid, 800.00);
    });

    test('CommissionHistoryItem parses server commission transaction payload', () {
      final json = {
        'id': 'comm_tx_9988',
        'orderId': 'ord_12345',
        'orderNumber': 'ORD-12345',
        'level': 2,
        'commissionBaseAmount': 1000.0,
        'commissionRate': 0.05,
        'commissionAmount': 50.0,
        'status': 'CONFIRMED',
        'createdAt': '2026-08-19T10:00:00Z',
      };

      final item = CommissionHistoryItem.fromJson(json);

      expect(item.id, 'comm_tx_9988');
      expect(item.orderId, 'ord_12345');
      expect(item.orderNumber, 'ORD-12345');
      expect(item.level, 2);
      expect(item.commissionBaseAmount, 1000.0);
      expect(item.commissionRate, 0.05);
      expect(item.commissionAmount, 50.0);
      expect(item.status, 'CONFIRMED');
      expect(item.createdAt, '2026-08-19T10:00:00Z');
    });

    test('ReferralInfo parses customer referral identity and sponsor', () {
      final json = {
        'partner': {
          'referralCode': 'REF9988',
          'referralLink': 'https://violeafy.com/ref/REF9988',
          'status': 'Active',
          'level': 'Gold',
        },
        'sponsor': {
          'id': 'CUST_SPONSOR_1',
          'name': 'John Sponsor',
          'status': 'Active',
        },
        'referralCount': 12,
        'qualifiedCount': 8,
        'commissionSummary': {
          'commissionEarned': 5000.0,
          'commissionPayable': 1500.0,
          'commissionPaid': 3500.0,
          'pending': 200.0,
          'confirmed': 4800.0,
        },
      };

      final info = ReferralInfo.fromJson(json);

      expect(info.referralCode, 'REF9988');
      expect(info.referralLink, 'https://violeafy.com/ref/REF9988');
      expect(info.partnerLevel, 'Gold');
      expect(info.referralCount, 12);
      expect(info.qualifiedCount, 8);
      expect(info.sponsor?.id, 'CUST_SPONSOR_1');
      expect(info.sponsor?.name, 'John Sponsor');
      expect(info.commissionSummary.payable, 1500.0);
      expect(info.commissionSummary.paid, 3500.0);
    });

    test('ReferralInfo handles nested fallback formats gracefully', () {
      final json = {
        'referralCode': 'REF1234',
        'partnerLevelName': 'Silver',
        'partnerStatus': 'Active',
        'totalReferrals': 5,
        'earnings': {
          'earned': 300.0,
          'payable': 100.0,
          'paid': 200.0,
        },
      };

      final info = ReferralInfo.fromJson(json);

      expect(info.referralCode, 'REF1234');
      expect(info.partnerLevel, 'Silver');
      expect(info.referralCount, 5);
      expect(info.commissionSummary.payable, 100.0);
      expect(info.commissionSummary.paid, 200.0);
    });

    test('ShoppingRepository filters leads to the logged-in user referral upline only', () {
      final currentUser = CustomerPerformance(
        id: 'cust_123',
        name: 'Alice Partner',
        company: 'Leafy',
        email: 'alice@example.com',
        mobileNumber: '9876543210',
        address: 'Bengaluru',
        state: 'Karnataka',
        district: 'Bengaluru Urban',
        totalSpent: 0,
        dealsClosed: 0,
        satisfactionScore: 0,
        lastOrderDate: '',
        tier: 'Gold',
        partnerName: 'Alice Partner',
        referralCode: 'REF_ALICE',
      );

      final leads = [
        Lead(
          id: 'lead_1',
          name: 'Lead One',
          email: 'lead1@example.com',
          phone: '9000000001',
          status: 'New',
          score: 25,
          source: 'WhatsApp',
          assignedTo: 'Tony Stark',
          createdAt: '2026-08-20T00:00:00Z',
          value: 15000,
          referralCode: 'REF_ALICE',
          referralPartner: 'Alice Partner',
        ),
        Lead(
          id: 'lead_2',
          name: 'Lead Two',
          email: 'lead2@example.com',
          phone: '9000000002',
          status: 'Qualified',
          score: 62,
          source: 'Amazon',
          assignedTo: 'Tony Stark',
          createdAt: '2026-08-20T00:00:00Z',
          value: 12000,
          referralCode: 'REF_BOB',
          referralPartner: 'Bob Partner',
        ),
        Lead(
          id: 'lead_3',
          name: 'Lead Three',
          email: 'lead3@example.com',
          phone: '9000000003',
          status: 'New',
          score: 40,
          source: 'Flipkart',
          assignedTo: 'Tony Stark',
          createdAt: '2026-08-20T00:00:00Z',
          value: 9000,
          referralCode: 'cust_123',
          referralPartner: 'Alice Partner',
        ),
      ];

      final filtered = ShoppingRepository.filterLeadsForCurrentUser(leads, currentUser);

      expect(filtered.length, 2);
      expect(filtered.map((lead) => lead.id).toList(), ['lead_1', 'lead_3']);
    });
  });
}
