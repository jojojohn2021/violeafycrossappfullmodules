import '../../models/models.dart';

/// Centralized utility for GST-inclusive price calculation, HSN-wise grouping,
/// and mandatory Pre-Order Booking Advance financial separation (Section 5).
class GstCalculator {
  static const double defaultGstRate = 18.0;
  static const String defaultHsnCode = '1234';

  /// Calculates GST-inclusive breakdown for a single regular sales item.
  /// Offered price is treated as GST-inclusive.
  /// Taxable Value = (Inclusive Amount * 100) / (100 + GST Rate)
  /// GST Amount = Inclusive Amount - Taxable Value
  static Map<String, dynamic> calculateItemGst({
    required double price,
    required int quantity,
    double? gstPercentage,
    String? hsnCode,
  }) {
    final rate = gstPercentage ?? defaultGstRate;
    final hsn = (hsnCode != null && hsnCode.trim().isNotEmpty)
        ? hsnCode.trim()
        : defaultHsnCode;
    final inclusiveAmount = double.parse((price * quantity).toStringAsFixed(2));
    final taxableValue =
        double.parse((inclusiveAmount / (1 + rate / 100)).toStringAsFixed(2));
    final gstAmount =
        double.parse((inclusiveAmount - taxableValue).toStringAsFixed(2));

    return {
      'hsnCode': hsn,
      'gstRate': rate,
      'inclusiveAmount': inclusiveAmount,
      'taxableValue': taxableValue,
      'gstAmount': gstAmount,
    };
  }

  /// Calculates regular sales Taxable Value, GST, Regular Invoice Grand Total,
  /// Pre-Order Booking Advance, and Customer Grand Total Payable.
  ///
  /// Mandatory Financial Rule (Section 5):
  /// - Pre-order advances are EXCLUDED from regular sales subtotal, taxable value,
  ///   regular GST, and Regular Invoice Grand Total.
  /// - Pre-order advances are ADDED to Regular Invoice Grand Total to produce
  ///   Customer Grand Total Payable.
  static GstCartSummary calculateCartSummary(
    List<SalesProduct> items, {
    double deliveryFee = 0.0,
    double discount = 0.0,
  }) {
    double totalTaxable = 0.0;
    double totalGst = 0.0;
    double regularSubtotal = 0.0;
    double totalPreorderAdvance = 0.0;
    double totalPreorderProductValue = 0.0;
    double totalPreorderRemainingBalance = 0.0;

    final hsnMap = <String, HsnGstSummaryItem>{};

    final regularItems = items.where((i) => !i.isPreorder).toList();
    final preorderItems = items.where((i) => i.isPreorder).toList();

    for (final item in regularItems) {
      final calc = calculateItemGst(
        price: item.price,
        quantity: item.quantity,
        gstPercentage: item.gstPercentage,
        hsnCode: item.hsnCode,
      );

      final String hsn = calc['hsnCode'];
      final double rate = calc['gstRate'];
      final double incAmount = calc['inclusiveAmount'];
      final double taxVal = calc['taxableValue'];
      final double gstVal = calc['gstAmount'];

      totalTaxable += taxVal;
      totalGst += gstVal;
      regularSubtotal += incAmount;

      final key = '$hsn|${rate.toStringAsFixed(2)}';
      if (hsnMap.containsKey(key)) {
        final existing = hsnMap[key]!;
        hsnMap[key] = HsnGstSummaryItem(
          hsnCode: hsn,
          gstRate: rate,
          taxableValue: double.parse(
              (existing.taxableValue + taxVal).toStringAsFixed(2)),
          gstAmount:
              double.parse((existing.gstAmount + gstVal).toStringAsFixed(2)),
          totalAmount: double.parse(
              (existing.totalAmount + incAmount).toStringAsFixed(2)),
        );
      } else {
        hsnMap[key] = HsnGstSummaryItem(
          hsnCode: hsn,
          gstRate: rate,
          taxableValue: taxVal,
          gstAmount: gstVal,
          totalAmount: incAmount,
        );
      }
    }

    for (final po in preorderItems) {
      final advance = po.bookingAdvance ?? po.price;
      final onlineUnit = po.onlinePriceSnapshot ?? po.price;
      final prodVal = po.totalProductValue ?? (onlineUnit * po.quantity);
      final remBal = po.remainingBalance ??
          (prodVal - advance > 0 ? prodVal - advance : 0.0);

      totalPreorderAdvance += advance;
      totalPreorderProductValue += prodVal;
      totalPreorderRemainingBalance += remBal;
    }

    final hsnSummaryList = hsnMap.values.toList()
      ..sort((a, b) => a.hsnCode.compareTo(b.hsnCode));

    final roundedRegularSubtotal =
        double.parse(regularSubtotal.toStringAsFixed(2));
    final hasRegularItems = regularItems.isNotEmpty && roundedRegularSubtotal > 0;
    final effectiveDeliveryFee = hasRegularItems ? deliveryFee : 0.0;
    final effectiveDiscount = hasRegularItems ? discount : 0.0;
    final regularInvoiceGrandTotal = hasRegularItems
        ? double.parse(
            (roundedRegularSubtotal + effectiveDeliveryFee - effectiveDiscount)
                .clamp(0.0, double.infinity)
                .toStringAsFixed(2),
          )
        : 0.0;
    final roundedPreorderAdvance =
        double.parse(totalPreorderAdvance.toStringAsFixed(2));
    final customerGrandTotalPayable = double.parse(
      (regularInvoiceGrandTotal + roundedPreorderAdvance).toStringAsFixed(2),
    );

    return GstCartSummary(
      totalTaxableValue: double.parse(totalTaxable.toStringAsFixed(2)),
      totalGstAmount: double.parse(totalGst.toStringAsFixed(2)),
      grandTotal: roundedRegularSubtotal,
      regularSalesSubtotal: roundedRegularSubtotal,
      regularInvoiceGrandTotal: regularInvoiceGrandTotal,
      totalPreorderBookingAdvance: roundedPreorderAdvance,
      totalPreorderProductValue:
          double.parse(totalPreorderProductValue.toStringAsFixed(2)),
      totalPreorderRemainingBalance:
          double.parse(totalPreorderRemainingBalance.toStringAsFixed(2)),
      customerGrandTotalPayable: customerGrandTotalPayable,
      hsnSummary: hsnSummaryList,
    );
  }
}

class GstCartSummary {
  final double totalTaxableValue;
  final double totalGstAmount;
  final double grandTotal;
  final double regularSalesSubtotal;
  final double regularInvoiceGrandTotal;
  final double totalPreorderBookingAdvance;
  final double totalPreorderProductValue;
  final double totalPreorderRemainingBalance;
  final double customerGrandTotalPayable;
  final List<HsnGstSummaryItem> hsnSummary;

  GstCartSummary({
    required this.totalTaxableValue,
    required this.totalGstAmount,
    required this.grandTotal,
    this.regularSalesSubtotal = 0.0,
    this.regularInvoiceGrandTotal = 0.0,
    this.totalPreorderBookingAdvance = 0.0,
    this.totalPreorderProductValue = 0.0,
    this.totalPreorderRemainingBalance = 0.0,
    this.customerGrandTotalPayable = 0.0,
    required this.hsnSummary,
  });
}
