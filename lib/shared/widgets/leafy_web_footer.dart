import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_providers.dart';

/// Leafyearth Production Domain
const String kProductionDomain = 'https://www.vamjo.com';

/// Web-Only Footer Component for Leafyearth Web Platform (https://www.vamjo.com)
class LeafyWebFooter extends ConsumerWidget {
  const LeafyWebFooter({super.key});

  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[LeafyWebFooter] Error launching URL $urlString: $e');
    }
  }

  void _onCategoryClick(BuildContext context, WidgetRef ref, String categoryName) {
    ref.read(selectedCategoryProvider.notifier).state = categoryName;
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Platform restriction: Render ONLY on Web platform (https://www.vamjo.com)
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: AppColors.card,
      margin: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 850;

                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. ONLINE SHOPPING
                          Expanded(
                            flex: 3,
                            child: _buildOnlineShoppingSection(context, ref),
                          ),
                          const SizedBox(width: 20),
                          // 2. CUSTOMER POLICIES
                          Expanded(
                            flex: 4,
                            child: _buildCustomerPoliciesSection(context),
                          ),
                          const SizedBox(width: 20),
                          // 3. EXPERIENCE LEAFYEARTH APP ON MOBILE
                          Expanded(
                            flex: 3,
                            child: _buildMobileAppSection(context),
                          ),
                          const SizedBox(width: 20),
                          // 4. LEARYAYUR
                          Expanded(
                            flex: 3,
                            child: _buildLearyayurSection(context),
                          ),
                        ],
                      );
                    } else {
                      // Stacked Layout for Mobile Web Browsers & Small Screens
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOnlineShoppingSection(context, ref),
                          const SizedBox(height: 28),
                          _buildCustomerPoliciesSection(context),
                          const SizedBox(height: 28),
                          _buildMobileAppSection(context),
                          const SizedBox(height: 28),
                          _buildLearyayurSection(context),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          // Bottom Copyright Bar
          Container(
            width: double.infinity,
            color: AppColors.secondaryBackground,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '© 2026 Leafyearth. All Rights Reserved. Powered by VAMJO.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Row(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => context.push('/privacy-policy'),
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const Text('  •  ', style: TextStyle(color: AppColors.textMuted)),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => context.push('/terms-and-conditions'),
                            child: const Text(
                              'T&C',
                              style: TextStyle(fontSize: 12, color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryGreen,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildFooterLinkItem({required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  // Section 1: ONLINE SHOPPING
  Widget _buildOnlineShoppingSection(BuildContext context, WidgetRef ref) {
    final categories = [
      'Kerala orgin Spices',
      'Nature Oils',
      'Home Made Masala',
      'Home Care',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('ONLINE SHOPPING'),
        ...categories.map(
          (cat) => _buildFooterLinkItem(
            label: cat,
            onTap: () => _onCategoryClick(context, ref, cat),
          ),
        ),
      ],
    );
  }

  // Section 2: CUSTOMER POLICIES (Strict Order)
  Widget _buildCustomerPoliciesSection(BuildContext context) {
    final policyLinks = <({String label, String route, bool isExternal, String? externalUrl})>[
      (label: 'Contact Us', route: '/contact-us', isExternal: false, externalUrl: null),
      (label: 'FAQ', route: '/faq', isExternal: false, externalUrl: null),
      (label: 'T&C', route: '/terms-and-conditions', isExternal: false, externalUrl: null),
      (label: 'Terms Of Use', route: '/terms-of-use', isExternal: false, externalUrl: null),
      (label: 'Track Orders', route: '/track-orders', isExternal: false, externalUrl: null),
      (label: 'Shipping', route: '/shipping', isExternal: false, externalUrl: null),
      (label: 'Cancellation', route: '/cancellation', isExternal: false, externalUrl: null),
      (label: 'Privacy policy', route: '/privacy-policy', isExternal: false, externalUrl: null),
      (label: 'Grievance Redressal', route: '/grievance-redressal', isExternal: false, externalUrl: null),
      (
        label: 'FSSAI Food Safety Connect app',
        route: '',
        isExternal: true,
        externalUrl: 'https://foodsafetyconnect.fssai.gov.in'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CUSTOMER POLICIES'),
        ...policyLinks.map(
          (item) => _buildFooterLinkItem(
            label: item.label,
            onTap: () {
              if (item.isExternal && item.externalUrl != null) {
                _launchExternalUrl(item.externalUrl!);
              } else {
                context.push(item.route);
              }
            },
          ),
        ),
      ],
    );
  }

  // Section 3: EXPERIENCE LEAFYEARTH APP ON MOBILE
  Widget _buildMobileAppSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('EXPERIENCE LEAFYEARTH APP ON MOBILE'),
        const SizedBox(height: 4),
        const Text(
          'Download the official Leafyearth Mobile Application for fast ordering & instant tracking.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        // Google Play Store Button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _launchExternalUrl('https://play.google.com/store/apps/details?id=com.vamjo.leafyearth'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shop, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GET IT ON', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text('Google Play', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Apple App Store Button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _launchExternalUrl('https://www.vamjo.com'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.apple, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Download on the', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text('App Store', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Section 4: LEARYAYUR
  Widget _buildLearyayurSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('LEARYAYUR'),
        const SizedBox(height: 4),
        const Text(
          'Discover authentic Ayurvedic products, organic wellness solutions & natural living with Learyayur by Leafyearth.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 14),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _launchExternalUrl('https://www.vamjo.com/learyayur'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.eco, color: AppColors.primaryGreen, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Explore Learyayur',
                    style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, color: AppColors.primaryGreen, size: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
