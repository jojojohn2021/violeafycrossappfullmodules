import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/api/preorder_api_client.dart';
import 'data/models/preorder_models.dart';
import 'data/repositories/preorder_repository.dart';
import 'domain/preorder_service.dart';
import 'presentation/screens/preorder_history_screen.dart';
import 'presentation/screens/preorder_screen.dart';

/// Riverpod Providers for the Pre-Order Booking Module.
final preorderApiClientProvider = Provider<PreorderApiClient>((ref) {
  return PreorderApiClient();
});

final preorderRepositoryProvider = Provider<PreorderRepository>((ref) {
  return PreorderRepository(ref.watch(preorderApiClientProvider));
});

final preorderServiceProvider = Provider<PreorderService>((ref) {
  return PreorderService(ref.watch(preorderRepositoryProvider));
});

final eligiblePreorderProductsProvider =
    FutureProvider.autoDispose<PreorderPagedResult<PreorderEligibleProduct>>(
        (ref) async {
  return ref.watch(preorderServiceProvider).getEligibleProducts(limit: 40);
});

final preorderCourierAgentsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(preorderServiceProvider).getCourierAgents();
});

final myPreordersProvider =
    FutureProvider.autoDispose<PreorderPagedResult<PreorderBooking>>(
        (ref) async {
  return ref.watch(preorderServiceProvider).getMyBookings(limit: 30);
});

final preorderDetailProvider = FutureProvider.autoDispose
    .family<PreorderBooking, String>((ref, preorderId) async {
  return ref.watch(preorderServiceProvider).getBookingById(preorderId);
});

/// GoRouter route registration helper for the Pre-Order Booking Module.
class PreorderModule {
  static const List<String> protectedRoutePrefixes = [
    '/preorders/history',
    '/preorders/detail',
  ];

  static List<GoRoute> routes(GlobalKey<NavigatorState> rootNavigatorKey) {
    return [
      GoRoute(
        path: '/preorders',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PreorderCatalogScreen(),
      ),
      GoRoute(
        path: '/preorders/history',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PreorderHistoryScreen(),
      ),
      GoRoute(
        path: '/preorders/detail/:preorderId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final preorderId = state.pathParameters['preorderId'] ?? '';
          return PreorderDetailScreen(preorderId: preorderId);
        },
      ),
    ];
  }
}
