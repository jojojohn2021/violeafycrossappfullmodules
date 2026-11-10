import 'dart:math';
import '../../../../models/models.dart';
import '../data/models/preorder_models.dart';
import '../data/repositories/preorder_repository.dart';

/// LeafyEarth Pre-Order Booking Module — Domain Service.
class PreorderService {
  final PreorderRepository _repository;

  PreorderService(this._repository);

  static const List<String> defaultCourierAgents = [
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

  /// Strict client-side guard: only products with `preorderactive == true` (Boolean) are eligible.
  /// All server operations independently re-verify this field on the backend.
  static bool isProductEligible(ProductPerformance product) =>
      product.preorderactive == true;

  /// Generates a cryptographic idempotency key for safe retries on network timeout.
  static String generateIdempotencyKey(String productId) {
    final rnd = Random.secure();
    final token =
        List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final cleanProd =
        productId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '').padRight(2, 'p');
    final prodPrefix =
        cleanProd.length > 16 ? cleanProd.substring(0, 16) : cleanProd;
    return 'idem_${prodPrefix}_$token';
  }

  /// Converts a validated [PreorderBooking] into a distinct [SalesProduct] pre-order cart item
  /// using [booking.bookingAdvance] as the payable amount.
  static SalesProduct toPreorderCartItem(PreorderBooking booking) {
    return SalesProduct(
      productId: booking.productId,
      productName: booking.productNameSnapshot,
      imageUrl: booking.imageUrlSnapshot,
      quantity: booking.quantity,
      price: booking.bookingAdvance,
      gstPercentage: booking.gstPercentageSnapshot,
      packingSize: booking.packingSizeSnapshot,
      unit: booking.packingSizeSnapshot,
      isPreorder: true,
      preorderId: booking.preorderId,
      onlinePriceSnapshot: booking.onlinePriceSnapshot,
      totalProductValue: booking.totalProductValue,
      paymentType: booking.paymentOption.wireValue,
      paymentTypeLabel: booking.paymentTypeLabel,
      bookingAdvance: booking.bookingAdvance,
      remainingBalance: booking.remainingBalance,
      giftWrap: booking.giftWrap,
      specialSuggestion: booking.specialSuggestion,
      expectedDeliveryDate: booking.expectedDeliveryDate,
      preferredCourierAgent: booking.preferredCourierAgent,
    );
  }

  Future<PreorderPagedResult<PreorderEligibleProduct>> getEligibleProducts({
    int limit = 20,
    String? cursor,
  }) =>
      _repository.fetchEligibleProducts(limit: limit, cursor: cursor);

  Future<List<String>> getCourierAgents() => _repository.fetchCourierAgents();

  Future<({PreorderBooking booking, bool idempotentReplay})> createPreorderBooking({
    required String productId,
    required int quantity,
    required PreorderPaymentOption paymentOption,
    required double bookingAdvance,
    required bool giftWrap,
    required String specialSuggestion,
    required String expectedDeliveryDate,
    required String preferredCourierAgent,
    required String idempotencyKey,
  }) =>
      _repository.submitPreorder(
        productId: productId,
        quantity: quantity,
        paymentOption: paymentOption,
        bookingAdvance: bookingAdvance,
        giftWrap: giftWrap,
        specialSuggestion: specialSuggestion,
        expectedDeliveryDate: expectedDeliveryDate,
        preferredCourierAgent: preferredCourierAgent,
        idempotencyKey: idempotencyKey,
      );

  Future<PreorderBooking> getBookingById(String preorderId) =>
      _repository.fetchBooking(preorderId);

  Future<PreorderPagedResult<PreorderBooking>> getMyBookings({
    int limit = 20,
    String? cursor,
  }) =>
      _repository.fetchMyBookings(limit: limit, cursor: cursor);

  Future<PreorderBooking> cancelBooking({
    required String preorderId,
    String? reason,
  }) =>
      _repository.cancelBooking(preorderId: preorderId, reason: reason);
}
