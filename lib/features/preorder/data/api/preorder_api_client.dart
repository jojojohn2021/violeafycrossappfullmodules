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

  static const List<String> allowedCourierAgents = [
    'Amazon Shipping',
    'Delhivery',
    'India Post',
    'DTDC',
  ];

  Future<List<String>> getCourierAgents() async {
    try {
      final res = Map<String, dynamic>.from(
        await _api.get('/api/v1/preorders/couriers'),
      );
      final allowedLower =
          allowedCourierAgents.map((e) => e.toLowerCase()).toSet();
      final list = ((res['courierAgents'] as List?) ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty && allowedLower.contains(e.toLowerCase()))
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return allowedCourierAgents;
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
    Map<String, dynamic>? deliveryAddress,
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
        if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
        'idempotencyKey': idempotencyKey,
      }),
    );
    return (
      booking: PreorderBooking.fromJson(
          Map<String, dynamic>.from(res['preorder'] as Map)),
      idempotentReplay: res['idempotentReplay'] == true,
    );
  }

  Future<PreorderBooking> updatePreorder({
    required String preorderId,
    Map<String, dynamic>? deliveryAddress,
    int? quantity,
    PreorderPaymentOption? paymentOption,
    double? bookingAdvance,
    bool? giftWrap,
    String? specialSuggestion,
    String? expectedDeliveryDate,
    String? preferredCourierAgent,
  }) async {
    final encoded = Uri.encodeComponent(preorderId);
    final res = Map<String, dynamic>.from(
      await _api.post('/api/v1/preorders/$encoded/update', {
        if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
        if (quantity != null) 'quantity': quantity,
        if (paymentOption != null) 'paymentType': paymentOption.wireValue,
        if (bookingAdvance != null) 'bookingAdvance': bookingAdvance,
        if (giftWrap != null) 'giftWrap': giftWrap,
        if (specialSuggestion != null) 'specialSuggestion': specialSuggestion,
        if (expectedDeliveryDate != null)
          'expectedDeliveryDate': expectedDeliveryDate,
        if (preferredCourierAgent != null)
          'preferredCourierAgent': preferredCourierAgent,
      }),
    );
    return PreorderBooking.fromJson(
        Map<String, dynamic>.from(res['preorder'] as Map));
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

  Future<Map<String, dynamic>> getBalanceQuote(String preorderId) async {
    final encoded = Uri.encodeComponent(preorderId);
    return Map<String, dynamic>.from(
      await _api.get('/api/v1/preorders/$encoded/balance'),
    );
  }

  Future<PreorderBalanceCheckoutQuote> createBalanceCheckout({
    required String preorderId,
    Map<String, dynamic>? deliveryAddress,
    String? idempotencyKey,
  }) async {
    final encoded = Uri.encodeComponent(preorderId);
    final res = Map<String, dynamic>.from(
      await _api.post('/api/v1/preorders/$encoded/balance-checkout', {
        if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotencyKey': idempotencyKey.trim(),
      }),
    );
    return PreorderBalanceCheckoutQuote.fromJson(res);
  }
}
