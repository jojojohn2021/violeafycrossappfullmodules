import 'package:flutter/material.dart';
import '../../../core/config/compliance_config.dart';
import '../../../core/theme/app_colors.dart';

class _PolicyLayout extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _PolicyLayout({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondaryBackground,
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

Widget _sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 18.0, bottom: 8.0),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.primaryGreen,
      ),
    ),
  );
}

Widget _paragraph(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12.0),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.5,
        color: AppColors.textPrimary,
      ),
    ),
  );
}

Widget _bullet(String label, String detail) {
  return Padding(
    padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// 7.1 Privacy Policy Screen (/privacy-policy)
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Privacy Policy',
      children: [
        Text(
          'Privacy Policy for ${ComplianceConfig.businessDisplayName}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text('Last updated: August 31, 2026 | ${ComplianceConfig.businessLegalName}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _paragraph(
            '${ComplianceConfig.businessDisplayName} ("we", "us", or "our"), operated by ${ComplianceConfig.businessLegalName}, is committed to protecting the privacy and security of your personal data. This Privacy Policy explains how we collect, use, store, and process your information when you access or use our Android, iOS, or Web application.'),
        _sectionHeader('1. Data We Collect'),
        _bullet('Account Information', 'Name, mobile number, email address, profile picture, and login credentials.'),
        _bullet('Delivery Information', 'Delivery address details, city, district, state, PIN code, and recipient contact info.'),
        _bullet('Order & Transaction Data', 'Order history, products purchased, GST details, payment transaction reference identifiers, and delivery status.'),
        _bullet('Device & Diagnostics', 'IP address, device type, OS version, app performance logs, and push notification tokens.'),
        _sectionHeader('2. How Payment Credentials Are Handled'),
        _paragraph(
            'Sensitive financial information (such as credit/debit card numbers, UPI PINs, net banking credentials, or CVVs) is processed directly by our PCI-DSS compliant payment gateway partner, Razorpay. VioleafyCross does not store, capture, or directly transmit sensitive card or banking credentials on our servers.'),
        _sectionHeader('3. Use of Data & Services'),
        _paragraph(
            'We use your data solely to fulfill orders, process payments via Razorpay, calculate applicable GST and delivery charges, provide customer support, manage referral commissions, and deliver service notifications via Firebase.'),
        _sectionHeader('4. Data Protection & Retention'),
        _paragraph(
            'Your data is protected using encrypted HTTPS communication (TLS 1.3) and secure cloud infrastructure. Account data is retained as long as your account is active. Order records and tax invoices are retained as mandated by applicable laws.'),
        _sectionHeader('5. Your Rights & Account Deletion'),
        _paragraph(
            'You have the right to access, update, or request the deletion of your personal account data. You can initiate account deletion directly within the mobile or web app via Profile > Account Settings > Delete Account, or by emailing ${ComplianceConfig.privacyEmail}.'),
        _sectionHeader('6. Contacting Privacy Support'),
        _paragraph(
            'If you have questions regarding this Privacy Policy, please contact our Privacy Team at ${ComplianceConfig.privacyEmail}.'),
      ],
    );
  }
}

/// 7.2 Terms and Conditions Screen (/terms-and-conditions)
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Terms & Conditions',
      children: [
        Text(
          'Terms & Conditions',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text('Operating Entity: ${ComplianceConfig.businessLegalName}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _paragraph(
            'Welcome to ${ComplianceConfig.businessDisplayName}. By accessing our web application or installing our Android or iOS applications, you agree to be bound by these Terms and Conditions.'),
        _sectionHeader('1. User Account & Responsibilities'),
        _paragraph(
            'You are responsible for maintaining the confidentiality of your mobile OTP / account login credentials and for restricting access to your device. You agree to provide accurate delivery and contact details for order processing.'),
        _sectionHeader('2. Product Pricing, GST & Orders'),
        _paragraph(
            'All product prices listed include applicable Goods and Services Tax (GST) as calculated by our server. Prices and availability are subject to change without prior notice. An order is confirmed only after successful payment authorization and server validation.'),
        _sectionHeader('3. Payment Processing via Razorpay'),
        _paragraph(
            'Payments on ${ComplianceConfig.businessDisplayName} are authorized and processed through Razorpay using server-verified signatures. Final payable amounts are calculated authoritatively by our server.'),
        _sectionHeader('4. Limitation of Liability & Applicable Law'),
        _paragraph(
            'These Terms shall be governed by and construed in accordance with the laws of India. Any disputes arising out of or in connection with these terms shall be subject to the exclusive jurisdiction of the courts in Bengaluru, Karnataka.'),
        _sectionHeader('5. Contact Details'),
        _paragraph(
            'For terms inquiries, please reach out to ${ComplianceConfig.supportEmail} or visit our Contact Us page.'),
      ],
    );
  }
}

/// 7.3 Shipping and Delivery Policy Screen (/shipping-and-delivery-policy)
class ShippingPolicyScreen extends StatelessWidget {
  const ShippingPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Shipping & Delivery Policy',
      children: [
        Text(
          'Shipping & Delivery Policy',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text('${ComplianceConfig.businessDisplayName} Logistics Rules', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Delivery Coverage & PIN Codes'),
        _paragraph(
            '${ComplianceConfig.businessDisplayName} ships products across supported PIN codes in India. Delivery availability and delivery charges are calculated dynamically based on your destination PIN code as determined by our server-side delivery engine.'),
        _sectionHeader('2. Delivery Timelines'),
        _paragraph(
            'Orders are typically processed within 24 to 48 hours following order confirmation. Standard estimated delivery times range from 2 to 7 business days depending on location.'),
        _sectionHeader('3. Delivery Charges'),
        _paragraph(
            'Applicable delivery fees are displayed at checkout before payment. Orders meeting minimum qualifying amounts or promotional criteria may receive free delivery as indicated during checkout.'),
        _sectionHeader('4. Order Tracking & Failed Deliveries'),
        _paragraph(
            'Once dispatched, tracking updates are available under "My Orders". In case of failed delivery attempts due to an incorrect address or customer unavailability, our logistics team will make up to two re-delivery attempts.'),
        _sectionHeader('5. Delivery Support'),
        _paragraph(
            'For any shipping queries or delivery delays, contact ${ComplianceConfig.supportEmail} or call ${ComplianceConfig.supportPhone}.'),
      ],
    );
  }
}

/// 7.4 Cancellation Policy Screen (/cancellation-policy)
class CancellationPolicyScreen extends StatelessWidget {
  const CancellationPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Cancellation Policy',
      children: [
        Text(
          'Cancellation Policy',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text('Order Cancellation Rules', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Order Cancellation Conditions'),
        _paragraph(
            'Customers may cancel an order free of charge before the order has been dispatched by logistics. Once an order is in transit, cancellations cannot be processed directly via the app.'),
        _sectionHeader('2. How to Request Cancellation'),
        _paragraph(
            'To cancel an eligible order, navigate to "My Orders" in the application and select "Cancel Order", or contact our customer support immediately at ${ComplianceConfig.supportEmail}.'),
        _sectionHeader('3. Payment & Refund Handling for Cancellations'),
        _paragraph(
            'If an order is cancelled prior to dispatch, the full payment amount will be refunded to the original payment source via Razorpay within 5 to 7 business days.'),
      ],
    );
  }
}

/// 7.5 Return and Refund Policy Screen (/return-and-refund-policy)
class ReturnRefundPolicyScreen extends StatelessWidget {
  const ReturnRefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Return & Refund Policy',
      children: [
        Text(
          'Return & Refund Policy',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text('Returns, Replacements & Refunds', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Return Eligibility'),
        _paragraph(
            'Items are eligible for return or replacement within 7 days of delivery if they are delivered damaged, defective, expired, or incorrect.'),
        _sectionHeader('2. Return Process'),
        _paragraph(
            'To request a return, go to "My Orders", select the order, and tap "Request Return". Provide a clear description and photo of the issue. Our support team will review and approve eligible requests.'),
        _sectionHeader('3. Refund Processing via Razorpay'),
        _paragraph(
            'Once returned items pass quality inspection, approved refunds are initiated through Razorpay back to your original payment account (UPI, credit/debit card, net banking). Refunds typically reflect within 5 to 7 working days.'),
        _sectionHeader('4. Non-Returnable Items'),
        _paragraph(
            'Certain personal care or perishable items may be marked non-returnable as indicated on product detail pages.'),
      ],
    );
  }
}

/// 7.6 Contact Us Screen (/contact-us)
class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Contact Us',
      children: [
        Text(
          'Customer Support & Contact Info',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(ComplianceConfig.businessLegalName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _bullet('Business Name', ComplianceConfig.businessLegalName),
        _bullet('Brand Name', ComplianceConfig.businessDisplayName),
        _bullet('Registered Address', ComplianceConfig.businessAddress),
        _bullet('Customer Support Email', ComplianceConfig.supportEmail),
        _bullet('Customer Support Phone', ComplianceConfig.supportPhone),
        _bullet('Privacy Officer Email', ComplianceConfig.privacyEmail),
        _sectionHeader('Grievance Redressal'),
        _bullet('Grievance Officer', ComplianceConfig.grievanceName),
        _bullet('Grievance Email', ComplianceConfig.grievanceEmail),
        const SizedBox(height: 16),
        const Text(
          'Our customer support team is available Monday to Saturday, 9:00 AM to 6:00 PM IST.',
          style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
