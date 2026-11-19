/// Validates dynamic banner CTA routes against the LeafyMart app's supported
/// GoRouter destinations before navigation.
class BannerRouteValidator {
  static const Set<String> _exactSupportedRoutes = {
    '/',
    '/categories',
    '/referrals',
    '/profile',
    '/cart',
    '/checkout',
    '/wallet',
    '/wishlist',
    '/orders',
    '/search',
    '/addresses',
    '/login',
    '/preorders',
    '/preorders/history',
    '/privacy-policy',
    '/terms-and-conditions',
    '/terms-of-use',
    '/shipping-policy',
    '/shipping-and-delivery-policy',
    '/shipping',
    '/cancellation-policy',
    '/cancellation',
    '/return-refund-policy',
    '/return-and-refund-policy',
    '/contact-us',
    '/grievance-redressal',
    '/faq',
    '/track-orders',
  };

  /// Safe aliases for routes used in Firestore banner documents that map to
  /// existing GoRouter screens without altering the router.
  static const Map<String, String> _routeAliases = {
    '/products': '/categories',
    '/shop': '/categories',
    '/home': '/',
  };

  static const List<String> _supportedDynamicPrefixes = [
    '/product-detail/',
    '/preorders/detail/',
  ];

  /// Returns a validated in-app route path, or `null` if [rawRoute] is not
  /// supported by the application router.
  static String? resolveSupportedRoute(String? rawRoute) {
    if (rawRoute == null) return null;
    final trimmed = rawRoute.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('/')) return null;

    // Reject scheme/protocol-relative injection attempts like //evil.com
    if (trimmed.startsWith('//')) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;

    final path = uri.path.isEmpty ? '/' : uri.path;
    final normalizedPath =
        (path.length > 1 && path.endsWith('/')) ? path.substring(0, path.length - 1) : path;

    final aliasTarget = _routeAliases[normalizedPath.toLowerCase()];
    if (aliasTarget != null) {
      return aliasTarget;
    }

    if (_exactSupportedRoutes.contains(normalizedPath)) {
      return normalizedPath;
    }

    for (final prefix in _supportedDynamicPrefixes) {
      if (normalizedPath.startsWith(prefix)) {
        final suffix = normalizedPath.substring(prefix.length).trim();
        if (suffix.isNotEmpty && !suffix.contains('/')) {
          return normalizedPath;
        }
      }
    }

    return null;
  }

  static bool isSupported(String? rawRoute) => resolveSupportedRoute(rawRoute) != null;
}
