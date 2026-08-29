import '../../models/models.dart';

/// Centralized utility for GST-inclusive price calculation and HSN-wise grouping.
class GstCalculator {
  static const double defaultGstRate = 18.0;
  static const String defaultHsnCode = '1234';

  /// Calculates GST-inclusive breakdown for a single item.
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
    final hsn = (hsnCode != null && hsnCode.trim().isNotEmpty) ? hsnCode.trim() : defaultHsnCode;
    final inclusiveAmount = double.parse((price * quantity).toStringAsFixed(2));
    final taxableValue = double.parse((inclusiveAmount / (1 + rate / 100)).toStringAsFixed(2));
    final gstAmount = double.parse((inclusiveAmount - taxableValue).toStringAsFixed(2));

    return {
      'hsnCode': hsn,
      'gstRate': rate,
      'inclusiveAmount': inclusiveAmount,
      'taxableValue': taxableValue,
      'gstAmount': gstAmount,
    };
  }

  /// Calculates total Taxable Value, Total GST, Grand Total, and HSN-wise GST Summary for a list of products.
  static GstCartSummary calculateCartSummary(List<SalesProduct> items) {
    double totalTaxable = 0.0;
    double totalGst = 0.0;
    double grandTotal = 0.0;

    final hsnMap = <String, HsnGstSummaryItem>{};

    for (final item in items) {
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
      grandTotal += incAmount;

      final key = '$hsn|${rate.toStringAsFixed(2)}';
      if (hsnMap.containsKey(key)) {
        final existing = hsnMap[key]!;
        hsnMap[key] = HsnGstSummaryItem(
          hsnCode: hsn,
          gstRate: rate,
          taxableValue: double.parse((existing.taxableValue + taxVal).toStringAsFixed(2)),
          gstAmount: double.parse((existing.gstAmount + gstVal).toStringAsFixed(2)),
          totalAmount: double.parse((existing.totalAmount + incAmount).toStringAsFixed(2)),
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

    final hsnSummaryList = hsnMap.values.toList()
      ..sort((a, b) => a.hsnCode.compareTo(b.hsnCode));

    return GstCartSummary(
      totalTaxableValue: double.parse(totalTaxable.toStringAsFixed(2)),
      totalGstAmount: double.parse(totalGst.toStringAsFixed(2)),
      grandTotal: double.parse(grandTotal.toStringAsFixed(2)),
      hsnSummary: hsnSummaryList,
    );
  }
}

class GstCartSummary {
  final double totalTaxableValue;
  final double totalGstAmount;
  final double grandTotal;
  final List<HsnGstSummaryItem> hsnSummary;

  GstCartSummary({
    required this.totalTaxableValue,
    required this.totalGstAmount,
    required this.grandTotal,
    required this.hsnSummary,
  });
}
