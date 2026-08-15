import 'package:flutter/material.dart';
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
import '../../features/profile/presentation/delivery_addresses_screen.dart';
import '../../features/auth/presentation/otp_login_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  onException: (context, state, router) {
    debugPrint('[Router] Ignored unhandled route exception for URI: ${state.uri}');
  },
  routes: [
    // Shell Route for 5 Bottom Nav Tabs with persistent Top App Bar
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
        // Tab 3: Search
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        // Tab 4: Wishlist
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/wishlist',
              builder: (context, state) => const WishlistScreen(),
            ),
          ],
        ),
        // Tab 5: Profile
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
      path: '/referrals',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReferralScreen(),
    ),
    GoRoute(
      path: '/orders',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OrdersScreen(),
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
