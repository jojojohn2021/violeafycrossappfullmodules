import '../../../../core/network/api_client.dart';
import '../models/preorder_models.dart';

/// LeafyEarth Pre-Order Booking Module — HTTP API Client.
/// Uses the existing [ApiClient] (with Firebase Auth ID token headers) and never accesses Firestore directly.
class PreorderApiClient {
  final ApiClient _api;

  PreorderApiClient([ApiClient? api]) : _api = api ?? ApiClient();

  Future<PreorderPagedResult<PreorderEligibleProduct>> getEligibleProducts({
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final res = Map<String, dynamic>.from(
      await _api.get(
          '/api/v1/preorders/eligible-products?${Uri(queryParameters: query).query}'),
    );
    final items = ((res['products'] as List?) ?? const [])
        .map((e) =>
            PreorderEligibleProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((p) => p.preorderactive == true)
        .toList();
    return PreorderPagedResult<PreorderEligibleProduct>(
      items: items,
      nextCursor: res['nextCursor'] as String?,
      total: (res['totalEligible'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<List<String>> getCourierAgents() async {
    try {
      final res = Map<String, dynamic>.from(
        await _api.get('/api/v1/preorders/couriers'),
      );
      final list = ((res['courierAgents'] as List?) ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return const [
      'India Post',
      'DTDC',
      'BlueDart',
      'Delhivery',
      'Professional Couriers',
      'ST Courier',
      'Trackon',
      'Ekart',
      'XpressBees',
      'Standard Courier',
    ];
  }

  Future<({PreorderBooking booking, bool idempotentReplay})> createPreorder({
    required String productId,
    required int quantity,
    required PreorderPaymentOption paymentOption,
    required double bookingAdvance,
    required bool giftWrap,
    required String specialSuggestion,
    required String expectedDeliveryDate,
    required String preferredCourierAgent,
    required String idempotencyKey,
  }) async {
    final res = Map<String, dynamic>.from(
      await _api.post('/api/v1/preorders', {
        'productId': productId,
        'quantity': quantity,
        'paymentType': paymentOption.wireValue,
        'bookingAdvance': bookingAdvance,
        'giftWrap': giftWrap,
        'specialSuggestion': specialSuggestion,
        'expectedDeliveryDate': expectedDeliveryDate,
        'preferredCourierAgent': preferredCourierAgent,
        'idempotencyKey': idempotencyKey,
      }),
    );
    return (
      booking: PreorderBooking.fromJson(
          Map<String, dynamic>.from(res['preorder'] as Map)),
      idempotentReplay: res['idempotentReplay'] == true,
    );
  }

  Future<PreorderBooking> getPreorderById(String preorderId) async {
    final encoded = Uri.encodeComponent(preorderId);
    final res =
        Map<String, dynamic>.from(await _api.get('/api/v1/preorders/$encoded'));
    return PreorderBooking.fromJson(
        Map<String, dynamic>.from(res['preorder'] as Map));
  }

  Future<PreorderPagedResult<PreorderBooking>> getMyPreorders({
    int limit = 20,
    String? cursor,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final res = Map<String, dynamic>.from(
      await _api
          .get('/api/v1/preorders/mine?${Uri(queryParameters: query).query}'),
    );
    final items = ((res['preorders'] as List?) ?? const [])
        .map((e) => PreorderBooking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return PreorderPagedResult<PreorderBooking>(
      items: items,
      nextCursor: res['nextCursor'] as String?,
    );
  }

  Future<PreorderBooking> cancelPreorder({
    required String preorderId,
    String? reason,
  }) async {
    final encoded = Uri.encodeComponent(preorderId);
    final res = Map<String, dynamic>.from(
      await _api.post('/api/v1/preorders/$encoded/cancel', {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );
    return PreorderBooking.fromJson(
        Map<String, dynamic>.from(res['preorder'] as Map));
  }
}
