import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:go_router/go_router.dart';
import '../../shared/widgets/bottom_navigation_shell.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/products/presentation/categories_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/wishlist/presentation/wishlist_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/products/presentation/product_detail_screen.dart';
import '../../features/cart_checkout/presentation/cart_screen.dart';
import '../../features/cart_checkout/presentation/checkout_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../../features/referral/presentation/referral_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/orders/presentation/invoice_screen.dart';
import '../../features/profile/presentation/delivery_addresses_screen.dart';
import '../../features/auth/presentation/otp_login_screen.dart';
import '../../models/models.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Turns the Firebase auth state stream into a Listenable so GoRouter can
/// re-evaluate `redirect` whenever the user signs in or out.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Single source of truth for which routes require an authenticated session.
// Everything else (Home, Shop/Categories, Search, Product details, Cart, Wishlist)
// stays publicly accessible for guests.
const _protectedPathPrefixes = ['/checkout', '/profile', '/referrals', '/wallet', '/addresses', '/orders'];

bool _isProtectedPath(String path) {
  return _protectedPathPrefixes.any((prefix) => path == prefix || path.startsWith('$prefix/'));
}

// Defensive helpers: Firebase may not be initialized yet (e.g. widget tests),
// in which case we simply treat the session as "not logged in" instead of throwing.
bool _isLoggedIn() {
  try {
    return firebase_auth.FirebaseAuth.instance.currentUser != null;
  } catch (_) {
    return false;
  }
}

Stream<dynamic> _authStateChanges() {
  try {
    return firebase_auth.FirebaseAuth.instance.authStateChanges();
  } catch (_) {
    return const Stream.empty();
  }
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: GoRouterRefreshStream(_authStateChanges()),
  redirect: (context, state) {
    final loggedIn = _isLoggedIn();
    final path = state.matchedLocation;

    if (!loggedIn && _isProtectedPath(path)) {
      final target = Uri.encodeComponent(state.uri.toString());
      return '/login?redirect=$target';
    }

    if (loggedIn && path == '/login') {
      final redirect = state.uri.queryParameters['redirect'];
      return (redirect == null || redirect.isEmpty) ? '/' : redirect;
    }

    return null;
  },
  onException: (context, state, router) {
    debugPrint('[Router] Ignored unhandled route exception for URI: ${state.uri}');
  },
  routes: [
    // Shell Route for 4 Bottom Nav Tabs with persistent Top App Bar
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return BottomNavigationShell(navigationShell: navigationShell);
      },
      branches: [
        // Tab 1: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // Tab 2: Categories
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/categories',
              builder: (context, state) => const CategoriesScreen(),
            ),
          ],
        ),
        // Tab 3: Lead Pipeline
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/referrals',
              builder: (context, state) => const ReferralScreen(),
            ),
          ],
        ),
        // Tab 4: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

    // Sub-routes outside shell
    GoRoute(
      path: '/product-detail/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'p1';
        return ProductDetailScreen(productId: id);
      },
    ),
    GoRoute(
      path: '/cart',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CartScreen(),
    ),
    GoRoute(
      path: '/checkout',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CheckoutScreen(),
    ),
    GoRoute(
      path: '/order-review',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final checkout = state.extra as CheckoutData;
        return OrderReviewScreen(data: checkout);
      },
    ),
    GoRoute(
      path: '/payment-result',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => PaymentResultScreen(
        transactionId: state.uri.queryParameters['txnid'] ?? '',
        status: state.uri.queryParameters['payment_status'] ?? 'failed',
      ),
    ),
    GoRoute(
      path: '/wallet',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WalletScreen(),
    ),
    GoRoute(
      path: '/wishlist',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WishlistScreen(),
    ),
    GoRoute(
      path: '/orders',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrdersScreen(),
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/orders/invoice',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => InvoiceScreen(order: state.extra as SalesOrder),
    ),
    GoRoute(
      path: '/addresses',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DeliveryAddressesScreen(),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => OtpLoginScreen(
        redirectTo: state.uri.queryParameters['redirect'] ?? '/',
      ),
    ),
    // Firebase Auth reCAPTCHA fallback web handler route
    // Just build the login screen. The SDK will handle the result automatically.
    GoRoute(
      path: '/__/auth/handler',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OtpLoginScreen(),
    ),
  ],
);
