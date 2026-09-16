import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/config/compliance_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/leafy_web_footer.dart';

class _PolicyLayout extends StatelessWidget {
  final String title;
  final String? webTitle;
  final List<Widget> children;

  const _PolicyLayout({required this.title, this.webTitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Title(
      color: AppColors.primaryGreen,
      title: 'Leafyearth - ${webTitle ?? title}',
      child: Scaffold(
        backgroundColor: AppColors.secondaryBackground,
        appBar: AppBar(
          title: Text(title),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
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
                ),
              ),
              if (kIsWeb) const LeafyWebFooter(),
            ],
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

/// 1. Privacy Policy Screen (/privacy-policy)
/// Publicly accessible HTTPS Privacy Policy for Leafyearth / VAMJO
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Privacy Policy',
      children: [
        Text(
          'Privacy Policy for Leafyearth',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Production Domain: https://www.vamjo.com | Authoritative Developer: VAMJO',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        const Text(
          'Last updated: September 16, 2026',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const Divider(height: 24),
        _paragraph(
            'Leafyearth ("we", "us", or "our"), developed and operated by VAMJO, is committed to safeguarding your privacy and personal data. This Privacy Policy governs the Leafyearth application across Android, iOS, and Web platforms (https://www.vamjo.com). It provides a complete and transparent explanation of how your information is collected, used, stored, processed, and protected.'),

        _sectionHeader('1. Application & Developer Identification'),
        _bullet('Application Name', 'Leafyearth'),
        _bullet('Developer & Operating Entity', 'VAMJO'),
        _bullet('Official Web Domain', 'https://www.vamjo.com'),
        _bullet('Authoritative Privacy Policy URL', 'https://www.vamjo.com/privacy-policy'),

        _sectionHeader('2. Personal & Sensitive Data We Collect'),
        _paragraph(
            'We collect and process personal data necessary for providing shopping services, order fulfillment, delivery logistics, account security, and customer support. Data collected includes:'),
        _bullet('Account & Profile Information', 'Your name, mobile phone number, email address, profile photo (avatar), and authentication credentials.'),
        _bullet('Delivery & Address Details', 'Recipient name, delivery address, city, district, state, PIN code, and recipient contact number.'),
        _bullet('Order & Transaction Records', 'Products purchased, order history, GST tax calculations, invoice references, and order status updates.'),
        _bullet('Referral & Partner Data', 'Referral codes, partner IDs, lead contact details submitted by user consent, and wallet cashback transaction history.'),
        _bullet('Device & Technical Information', 'IP address, device model, operating system version, browser user-agent, application performance logs, and Firebase Cloud Messaging (FCM) push notification tokens.'),

        _sectionHeader('3. Payment Credentials & Financial Security'),
        _paragraph(
            'All payment transactions (UPI, Credit/Debit Cards, Net Banking) are securely authorized and processed through our PCI-DSS compliant payment gateway partner, Razorpay. Leafyearth does not capture, store, or transmit sensitive financial credentials (such as card numbers, CVVs, or UPI PINs) on our servers.'),

        _sectionHeader('4. Purpose of Data Collection'),
        _paragraph('Your personal information is collected and processed exclusively for legitimate business purposes:'),
        _bullet('Account Creation & Authentication', 'Verifying user identity via mobile OTP and securing user account access.'),
        _bullet('Order Processing & Fulfillment', 'Calculating prices, applying GST tax rules, and dispatching products to your designated address.'),
        _bullet('Delivery Logistics', 'Sharing recipient contact details and address lines with verified shipping carriers for timely package delivery.'),
        _bullet('Customer Support & Grievance', 'Addressing customer inquiries, resolving order discrepancies, and facilitating replacements/refunds.'),
        _bullet('Referral & Wallet Operations', 'Processing partner referral payouts and maintaining wallet cashback balances.'),
        _bullet('Legal & Regulatory Compliance', 'Maintaining tax invoices, transaction logs, and statutory audit trails as required by Indian taxation laws.'),

        _sectionHeader('5. Third-Party Service Providers'),
        _paragraph(
            'We share data only with trusted third-party service providers essential for application operations. Each third party handles data strictly in compliance with data protection standards:'),
        _bullet('Firebase (Google LLC)', 'Cloud database (Firestore), user authentication, secure image storage, and push notifications.'),
        _bullet('Razorpay Software Private Limited', 'PCI-DSS certified payment gateway for processing online payments and refunds.'),
        _bullet('Logistics & Courier Partners', 'Third-party delivery services receiving recipient delivery address and phone number for parcel shipment.'),
        _bullet('Google Cloud Services', 'Hosting infrastructure and system performance analytics.'),

        _sectionHeader('6. Security Measures'),
        _paragraph(
            'Leafyearth implements industry-standard technical and organizational security controls:'),
        _bullet('HTTPS / TLS 1.3 Encryption', 'All communication between your device and our web server is encrypted in transit.'),
        _bullet('Access Control & Authentication', 'Strict role-based administrative access and server-verified authorization checks.'),
        _bullet('Secure Credential Management', 'API keys and secret credentials managed via Google Cloud Secret Manager.'),

        _sectionHeader('7. Data Retention Policy'),
        _paragraph(
            'Personal profile data is retained for as long as your account remains active. Transactional order records, GST invoices, and financial ledgers are retained for a statutory minimum period of 7 years as mandated under Indian tax regulations.'),

        _sectionHeader('8. Account Deletion & Associated Data Removal'),
        _paragraph(
            'You have the right to request the complete deletion of your account and personal data at any time:'),
        _bullet('In-App Account Deletion', 'Navigate to Profile > Request Account & Data Deletion in the mobile app or web platform (https://www.vamjo.com). Selecting this option immediately invalidates login sessions and permanently deletes profile data, saved addresses, and user preferences.'),
        _bullet('Email Deletion Request', 'Alternatively, send an email to info@vamjo.com or sales@vamjo.com with the subject "Account Deletion Request" from your registered email address.'),
        _paragraph(
            'Upon processing, your profile and personal data will be deleted. Statutorily mandated tax invoices and order audit logs will be retained securely for regulatory compliance.'),

        _sectionHeader('9. Privacy Contact Information'),
        _paragraph('For any questions, concerns, or requests regarding this Privacy Policy, please contact our privacy officer:'),
        _bullet('Operating Entity', 'VAMJO'),
        _bullet('Privacy Email', 'info@vamjo.com'),
        _bullet('Customer Support Email', 'sales@vamjo.com'),
        _bullet('Support Phone', '+91 8547927539'),
        _bullet('Registered Address', '3/286 Panamkoodan Commerial Corner, kallettumkara, Thrissur, Kerala, 680683'),
      ],
    );
  }
}

/// 2. Terms and Conditions Screen (/terms-and-conditions & /terms-of-use)
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Terms & Conditions',
      webTitle: 'Terms of Use',
      children: [
        Text(
          'Terms & Conditions',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text('Operating Entity: VAMJO | Platform: Leafyearth (https://www.vamjo.com)',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _paragraph(
            'Welcome to Leafyearth. By accessing our web application (https://www.vamjo.com) or installing our mobile applications, you agree to be bound by these Terms and Conditions.'),
        _sectionHeader('1. User Account & Responsibilities'),
        _paragraph(
            'You are responsible for maintaining the confidentiality of your mobile OTP login credentials. You agree to provide accurate recipient contact and delivery details for order execution.'),
        _sectionHeader('2. Product Pricing, GST & Orders'),
        _paragraph(
            'All product prices include applicable Goods and Services Tax (GST). Prices and availability are subject to change without notice. Orders are confirmed upon payment authorization and server validation.'),
        _sectionHeader('3. Payment Processing via Razorpay'),
        _paragraph(
            'Payments on Leafyearth are authorized and processed securely through Razorpay using server-verified signatures.'),
        _sectionHeader('4. Contact Details'),
        _paragraph('For terms inquiries, contact sales@vamjo.com or visit our Contact Us page.'),
      ],
    );
  }
}

/// 3. Shipping and Delivery Policy Screen (/shipping-policy & /shipping)
class ShippingPolicyScreen extends StatelessWidget {
  const ShippingPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Shipping & Delivery Policy',
      webTitle: 'Shipping Policy',
      children: [
        Text(
          'Shipping & Delivery Policy',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text('Leafyearth Logistics Rules | Domain: https://www.vamjo.com',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Delivery Coverage & PIN Codes'),
        _paragraph(
            'Leafyearth ships products across supported PIN codes in India. Delivery availability and delivery charges are calculated dynamically based on your destination PIN code.'),
        _sectionHeader('2. Delivery Timelines'),
        _paragraph(
            'Orders are typically processed within 24 to 48 hours following order confirmation. Estimated delivery times range from 2 to 7 business days.'),
        _sectionHeader('3. Order Tracking'),
        _paragraph('Once dispatched, tracking updates are accessible under "My Orders".'),
        _sectionHeader('4. Delivery Support'),
        _paragraph('For shipping queries, contact sales@vamjo.com or call +91 8547927539.'),
      ],
    );
  }
}

/// 4. Cancellation Policy Screen (/cancellation-policy & /cancellation)
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
        const Text('Order Cancellation Rules', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Order Cancellation Conditions'),
        _paragraph('Customers may cancel an order before dispatch via My Orders or by contacting customer support.'),
        _sectionHeader('2. Refund Handling for Cancellations'),
        _paragraph('Cancelled orders prior to dispatch receive full refunds to the original payment source via Razorpay within 5 to 7 business days.'),
      ],
    );
  }
}

/// 5. Return and Refund Policy Screen (/return-refund-policy)
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
        const Text('Returns, Replacements & Refunds', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('1. Return Eligibility'),
        _paragraph('Items delivered damaged, defective, or incorrect are eligible for return or replacement within 7 days of delivery.'),
        _sectionHeader('2. Refund Processing'),
        _paragraph('Approved refunds are processed via Razorpay back to your original payment method within 5 to 7 business days.'),
      ],
    );
  }
}

/// 6. Contact Us Screen (/contact-us & /grievance-redressal)
class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Contact Us',
      webTitle: 'Contact Us & Grievance Redressal',
      children: [
        Text(
          'Customer Support & Contact Info',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text('Operating Entity: VAMJO | Platform: Leafyearth', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _bullet('Operating Entity', ComplianceConfig.businessLegalName),
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

/// 7. FAQ Screen (/faq)
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PolicyLayout(
      title: 'Frequently Asked Questions',
      webTitle: 'FAQ',
      children: [
        Text(
          'Frequently Asked Questions (FAQ)',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text('Leafyearth Customer Support Center', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Divider(height: 24),
        _sectionHeader('Q: How do I place an order on Leafyearth?'),
        _paragraph('Browse products, add your desired items to the cart, enter your delivery address PIN code, and proceed to checkout using Razorpay UPI, card, or net banking.'),
        _sectionHeader('Q: What payment methods are accepted?'),
        _paragraph('We accept UPI (Google Pay, PhonePe, Paytm), Credit Cards, Debit Cards, Net Banking, and Wallet payments authorized securely through Razorpay.'),
        _sectionHeader('Q: How do I track my order?'),
        _paragraph('Navigate to "My Orders" in the application to view real-time delivery status and tracking details.'),
        _sectionHeader('Q: How can I request account deletion?'),
        _paragraph('Go to Profile > Request Account & Data Deletion in the mobile app or web platform (https://www.vamjo.com), or email info@vamjo.com.'),
      ],
    );
  }
}
