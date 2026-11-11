import '../api/preorder_api_client.dart';
import '../models/preorder_models.dart';

/// LeafyEarth Pre-Order Booking Module — Repository Layer.
class PreorderRepository {
  final PreorderApiClient _apiClient;

  PreorderRepository([PreorderApiClient? apiClient])
      : _apiClient = apiClient ?? PreorderApiClient();

  Future<PreorderPagedResult<PreorderEligibleProduct>> fetchEligibleProducts({
    int limit = 20,
    String? cursor,
  }) =>
      _apiClient.getEligibleProducts(limit: limit, cursor: cursor);

  Future<List<String>> fetchCourierAgents() => _apiClient.getCourierAgents();

  Future<({PreorderBooking booking, bool idempotentReplay})> submitPreorder({
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
  }) =>
      _apiClient.createPreorder(
        productId: productId,
        quantity: quantity,
        paymentOption: paymentOption,
        bookingAdvance: bookingAdvance,
        giftWrap: giftWrap,
        specialSuggestion: specialSuggestion,
        expectedDeliveryDate: expectedDeliveryDate,
        preferredCourierAgent: preferredCourierAgent,
        idempotencyKey: idempotencyKey,
        deliveryAddress: deliveryAddress,
      );

  Future<PreorderBooking> updateBooking({
    required String preorderId,
    Map<String, dynamic>? deliveryAddress,
    int? quantity,
    PreorderPaymentOption? paymentOption,
    double? bookingAdvance,
    bool? giftWrap,
    String? specialSuggestion,
    String? expectedDeliveryDate,
    String? preferredCourierAgent,
  }) =>
      _apiClient.updatePreorder(
        preorderId: preorderId,
        deliveryAddress: deliveryAddress,
        quantity: quantity,
        paymentOption: paymentOption,
        bookingAdvance: bookingAdvance,
        giftWrap: giftWrap,
        specialSuggestion: specialSuggestion,
        expectedDeliveryDate: expectedDeliveryDate,
        preferredCourierAgent: preferredCourierAgent,
      );

  Future<PreorderBooking> fetchBooking(String preorderId) =>
      _apiClient.getPreorderById(preorderId);

  Future<PreorderPagedResult<PreorderBooking>> fetchMyBookings({
    int limit = 20,
    String? cursor,
  }) =>
      _apiClient.getMyPreorders(limit: limit, cursor: cursor);

  Future<PreorderBooking> cancelBooking({
    required String preorderId,
    String? reason,
  }) =>
      _apiClient.cancelPreorder(preorderId: preorderId, reason: reason);
}
