/// LeafyEarth Pre-Order Booking Module — Data Models, Validators & DTOs.
/// No direct Firestore / Realtime Database dependencies.
library;

enum PreorderBookingStatus {
  pendingPayment,
  confirmed,
  processing,
  readyForDispatch,
  dispatched,
  delivered,
  cancelled;

  static PreorderBookingStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'confirmed':
        return PreorderBookingStatus.confirmed;
      case 'processing':
      case 'preparing':
        return PreorderBookingStatus.processing;
      case 'ready_for_dispatch':
      case 'ready':
        return PreorderBookingStatus.readyForDispatch;
      case 'dispatched':
        return PreorderBookingStatus.dispatched;
      case 'delivered':
      case 'fulfilled':
        return PreorderBookingStatus.delivered;
      case 'cancelled':
        return PreorderBookingStatus.cancelled;
      case 'pending_payment':
      case 'pending':
      default:
        return PreorderBookingStatus.pendingPayment;
    }
  }

  String get wireValue {
    switch (this) {
      case PreorderBookingStatus.pendingPayment:
        return 'pending_payment';
      case PreorderBookingStatus.confirmed:
        return 'confirmed';
      case PreorderBookingStatus.processing:
        return 'processing';
      case PreorderBookingStatus.readyForDispatch:
        return 'ready_for_dispatch';
      case PreorderBookingStatus.dispatched:
        return 'dispatched';
      case PreorderBookingStatus.delivered:
        return 'delivered';
      case PreorderBookingStatus.cancelled:
        return 'cancelled';
    }
  }

  String get displayLabel {
    switch (this) {
      case PreorderBookingStatus.pendingPayment:
        return 'Pending Payment';
      case PreorderBookingStatus.confirmed:
        return 'Confirmed';
      case PreorderBookingStatus.processing:
        return 'Processing';
      case PreorderBookingStatus.readyForDispatch:
        return 'Ready for Dispatch';
      case PreorderBookingStatus.dispatched:
        return 'Dispatched';
      case PreorderBookingStatus.delivered:
        return 'Delivered';
      case PreorderBookingStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Alias kept for UI status badge compatibility
typedef PreorderStatus = PreorderBookingStatus;

enum PreorderPaymentStatus {
  unpaid,
  pending,
  partiallyPaid,
  paid,
  failed,
  refunded;

  static PreorderPaymentStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pending':
        return PreorderPaymentStatus.pending;
      case 'partially_paid':
        return PreorderPaymentStatus.partiallyPaid;
      case 'paid':
        return PreorderPaymentStatus.paid;
      case 'failed':
        return PreorderPaymentStatus.failed;
      case 'refunded':
        return PreorderPaymentStatus.refunded;
      case 'unpaid':
      default:
        return PreorderPaymentStatus.unpaid;
    }
  }

  String get wireValue {
    switch (this) {
      case PreorderPaymentStatus.unpaid:
        return 'unpaid';
      case PreorderPaymentStatus.pending:
        return 'pending';
      case PreorderPaymentStatus.partiallyPaid:
        return 'partially_paid';
      case PreorderPaymentStatus.paid:
        return 'paid';
      case PreorderPaymentStatus.failed:
        return 'failed';
      case PreorderPaymentStatus.refunded:
        return 'refunded';
    }
  }

  String get displayLabel {
    switch (this) {
      case PreorderPaymentStatus.unpaid:
        return 'Unpaid';
      case PreorderPaymentStatus.pending:
        return 'Pending Verification';
      case PreorderPaymentStatus.partiallyPaid:
        return 'Partially Paid (Advance)';
      case PreorderPaymentStatus.paid:
        return 'Paid in Full';
      case PreorderPaymentStatus.failed:
        return 'Payment Failed';
      case PreorderPaymentStatus.refunded:
        return 'Refunded';
    }
  }
}

enum PreorderPaymentOption {
  full,
  partial;

  String get wireValue => this == PreorderPaymentOption.full ? 'full' : 'partial';

  String get displayLabel =>
      this == PreorderPaymentOption.full ? 'Full Amount' : 'Partial Payment';

  static PreorderPaymentOption fromString(String? raw) {
    final lower = (raw ?? '').trim().toLowerCase();
    if (lower == 'partial' || lower == 'partial payment' || lower == 'partial_payment') {
      return PreorderPaymentOption.partial;
    }
    return PreorderPaymentOption.full;
  }
}

/// Strictly evaluates whether a raw JSON value for `preorderactive` is the Boolean `true`.
/// Missing, null, false, "true" (string), 1, or any other values return `false`.
bool isStrictPreorderActive(dynamic rawValue) => rawValue is bool && rawValue == true;

/// Rounds currency to 2 decimal places.
double roundPreorderCurrency(double value) =>
    double.parse(value.toStringAsFixed(2));

/// Validates and calculates Booking Advance and Remaining Balance (Section 3.1).
class PreorderAdvanceValidationResult {
  final bool isValid;
  final String? errorMessage;
  final double onlinePrice;
  final int quantity;
  final double totalProductValue;
  final double minBookingAdvance;
  final double maxBookingAdvance;
  final double bookingAdvance;
  final double remainingBalance;

  const PreorderAdvanceValidationResult({
    required this.isValid,
    this.errorMessage,
    required this.onlinePrice,
    required this.quantity,
    required this.totalProductValue,
    required this.minBookingAdvance,
    required this.maxBookingAdvance,
    required this.bookingAdvance,
    required this.remainingBalance,
  });
}

class PreorderAdvanceValidator {
  static const double minAdvanceRatio = 0.10; // 10%
  static const double maxAdvanceRatio = 1.00; // 100%

  static PreorderAdvanceValidationResult validateAndCalculate({
    required double onlinePrice,
    required int quantity,
    required PreorderPaymentOption paymentOption,
    String? partialInputText,
  }) {
    final safeQty = quantity < 1 ? 1 : quantity;
    final safeUnit = roundPreorderCurrency(onlinePrice);
    final totalValue = roundPreorderCurrency(safeUnit * safeQty);
    final minAdvance = roundPreorderCurrency(totalValue * minAdvanceRatio);
    final maxAdvance = roundPreorderCurrency(totalValue * maxAdvanceRatio);

    if (paymentOption == PreorderPaymentOption.full) {
      return PreorderAdvanceValidationResult(
        isValid: totalValue > 0,
        errorMessage: totalValue > 0 ? null : 'Invalid product price.',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: totalValue,
        remainingBalance: 0.0,
      );
    }

    final raw = (partialInputText ?? '').trim();
    if (raw.isEmpty) {
      return PreorderAdvanceValidationResult(
        isValid: false,
        errorMessage:
            'Please enter a Booking Advance (minimum ₹${minAdvance.toStringAsFixed(2)}).',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: 0.0,
        remainingBalance: totalValue,
      );
    }

    final parsed = double.tryParse(raw);
    if (parsed == null || !parsed.isFinite) {
      return PreorderAdvanceValidationResult(
        isValid: false,
        errorMessage: 'Booking Advance must be a valid numeric amount.',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: 0.0,
        remainingBalance: totalValue,
      );
    }

    if (parsed <= 0) {
      return PreorderAdvanceValidationResult(
        isValid: false,
        errorMessage: 'Booking Advance must be greater than zero.',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: 0.0,
        remainingBalance: totalValue,
      );
    }

    final roundedAdvance = roundPreorderCurrency(parsed);
    if (roundedAdvance < minAdvance - 0.001) {
      return PreorderAdvanceValidationResult(
        isValid: false,
        errorMessage:
            'Minimum Booking Advance is 10% (₹${minAdvance.toStringAsFixed(2)}).',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: roundedAdvance,
        remainingBalance: roundPreorderCurrency(
          (totalValue - roundedAdvance).clamp(0.0, totalValue),
        ),
      );
    }

    if (roundedAdvance > maxAdvance + 0.001) {
      return PreorderAdvanceValidationResult(
        isValid: false,
        errorMessage:
            'Booking Advance cannot exceed 100% of product value (₹${maxAdvance.toStringAsFixed(2)}).',
        onlinePrice: safeUnit,
        quantity: safeQty,
        totalProductValue: totalValue,
        minBookingAdvance: minAdvance,
        maxBookingAdvance: maxAdvance,
        bookingAdvance: roundedAdvance,
        remainingBalance: 0.0,
      );
    }

    final remaining = roundPreorderCurrency(
      (totalValue - roundedAdvance).clamp(0.0, totalValue),
    );
    return PreorderAdvanceValidationResult(
      isValid: true,
      errorMessage: null,
      onlinePrice: safeUnit,
      quantity: safeQty,
      totalProductValue: totalValue,
      minBookingAdvance: minAdvance,
      maxBookingAdvance: maxAdvance,
      bookingAdvance: roundedAdvance,
      remainingBalance: remaining,
    );
  }

  /// Validates that [selectedDate] is strictly a future calendar date (after today).
  static bool isFutureDeliveryDate(DateTime? selectedDate, {DateTime? now}) {
    if (selectedDate == null) return false;
    final ref = now ?? DateTime.now();
    final todayDateOnly = DateTime(ref.year, ref.month, ref.day);
    final targetDateOnly =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    return targetDateOnly.isAfter(todayDateOnly);
  }

  /// Formats a [DateTime] as `YYYY-MM-DD`.
  static String formatDateYyyyMmDd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class PreorderEligibleProduct {
  final String id;
  final String name;
  final String sku;
  final String packingSize;
  final String unit;
  final double onlinePrice;
  final double? offerPrice;
  final double effectivePrice;
  final double mrp;
  final double gstPercentage;
  final String? imageUrl;
  final List<String> images;
  final String category;
  final String? brand;
  final String? description;
  final bool preorderactive;
  final List<String> uniqueSpecs;
  final double? rating;
  final int? reviewsCount;

  const PreorderEligibleProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.packingSize,
    required this.unit,
    required this.onlinePrice,
    this.offerPrice,
    required this.effectivePrice,
    required this.mrp,
    required this.gstPercentage,
    this.imageUrl,
    this.images = const [],
    this.category = '',
    this.brand,
    this.description,
    required this.preorderactive,
    this.uniqueSpecs = const [],
    this.rating,
    this.reviewsCount,
  });

  bool get hasDiscount => mrp > effectivePrice && effectivePrice > 0;
  int get discountPercent =>
      hasDiscount ? (((mrp - effectivePrice) / mrp) * 100).round() : 0;

  factory PreorderEligibleProduct.fromJson(Map<String, dynamic> json) {
    final online = (json['onlinePrice'] as num?)?.toDouble() ?? 0.0;
    final offer = (json['offerPrice'] as num?)?.toDouble();
    final effective = (json['effectivePrice'] as num?)?.toDouble() ??
        (offer != null && offer > 0 ? offer : online);
    final mrpVal = (json['mrp'] as num?)?.toDouble() ?? effective;

    return PreorderEligibleProduct(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      sku: '${json['sku'] ?? ''}',
      packingSize: '${json['packingSize'] ?? ''}',
      unit: '${json['unit'] ?? ''}',
      onlinePrice: online,
      offerPrice: offer,
      effectivePrice: effective,
      mrp: mrpVal >= effective ? mrpVal : effective,
      gstPercentage: (json['gstPercentage'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl']?.toString(),
      images: (json['images'] is List)
          ? (json['images'] as List).map((e) => '$e').toList()
          : const [],
      category: '${json['category'] ?? ''}',
      brand: json['brand']?.toString(),
      description: json['description']?.toString(),
      preorderactive: isStrictPreorderActive(json['preorderactive']),
      uniqueSpecs: (json['uniqueSpecs'] is List)
          ? (json['uniqueSpecs'] as List).map((e) => '$e').toList()
          : const [],
      rating: (json['rating'] as num?)?.toDouble(),
      reviewsCount: (json['reviewsCount'] as num?)?.toInt(),
    );
  }
}

class PreorderDeliveryAddress {
  final String? id;
  final String name;
  final String mobileNumber;
  final String? email;
  final String addressLine;
  final String city;
  final String district;
  final String state;
  final String pincode;
  final String formattedAddress;

  const PreorderDeliveryAddress({
    this.id,
    this.name = '',
    this.mobileNumber = '',
    this.email,
    this.addressLine = '',
    this.city = '',
    this.district = '',
    this.state = '',
    this.pincode = '',
    this.formattedAddress = '',
  });

  bool get isNotEmpty =>
      addressLine.isNotEmpty ||
      city.isNotEmpty ||
      district.isNotEmpty ||
      state.isNotEmpty ||
      pincode.isNotEmpty ||
      formattedAddress.isNotEmpty;

  String get displaySummary {
    if (formattedAddress.isNotEmpty) return formattedAddress;
    final parts = [
      addressLine,
      city,
      district,
      state,
    ].where((p) => p.trim().isNotEmpty).toList();
    var line = parts.join(', ');
    if (pincode.trim().isNotEmpty) {
      line = line.isNotEmpty ? '$line - $pincode' : pincode;
    }
    if (name.trim().isNotEmpty) {
      final header = mobileNumber.trim().isNotEmpty
          ? '$name ($mobileNumber)'
          : name;
      line = line.isNotEmpty ? '$header, $line' : header;
    }
    return line;
  }

  Map<String, dynamic> toJson() => {
        if (id != null && id!.isNotEmpty) 'id': id,
        'name': name,
        'mobileNumber': mobileNumber,
        if (email != null && email!.isNotEmpty) 'email': email,
        'addressLine': addressLine,
        'city': city,
        'district': district,
        'state': state,
        'pincode': pincode,
        'formattedAddress': displaySummary,
      };

  factory PreorderDeliveryAddress.fromJson(Map<String, dynamic> json) {
    return PreorderDeliveryAddress(
      id: json['id']?.toString(),
      name: '${json['name'] ?? json['deliveryAddressName'] ?? ''}',
      mobileNumber:
          '${json['mobileNumber'] ?? json['deliveryAddressMobile'] ?? ''}',
      email: (json['email'] ?? json['deliveryAddressEmail'])?.toString(),
      addressLine:
          '${json['addressLine'] ?? json['deliveryAddressLine'] ?? json['address'] ?? ''}',
      city: '${json['city'] ?? json['deliveryCity'] ?? ''}',
      district: '${json['district'] ?? json['deliveryDistrict'] ?? ''}',
      state: '${json['state'] ?? json['deliveryState'] ?? ''}',
      pincode: '${json['pincode'] ?? json['deliveryPincode'] ?? ''}',
      formattedAddress:
          '${json['formattedAddress'] ?? json['formattedDeliveryAddress'] ?? ''}',
    );
  }
}

class PreorderBooking {
  final String preorderId;
  final String userId;
  final String customerId;
  final String customerDisplayName;
  final String productId;
  final String productNameSnapshot;
  final String skuSnapshot;
  final String packingSizeSnapshot;
  final String? imageUrlSnapshot;
  final int quantity;
  final double onlinePriceSnapshot;
  final double mrpSnapshot;
  final double gstPercentageSnapshot;
  final double totalProductValue;
  final PreorderPaymentOption paymentOption;
  final String paymentTypeLabel;
  final double bookingAdvance;
  final double initialBookingAdvance;
  final double totalVerifiedPaid;
  final double remainingBalance;
  final bool giftWrap;
  final String specialSuggestion;
  final String expectedDeliveryDate;
  final String preferredCourierAgent;
  final PreorderDeliveryAddress? deliveryAddress;
  final String formattedDeliveryAddress;
  final String currency;
  final PreorderBookingStatus bookingStatus;
  final PreorderPaymentStatus paymentStatus;
  final String? paymentReference;
  final String? lastPaymentReference;
  final String? checkoutReference;
  final String? invoiceId;
  final String? salesOrderId;
  final String? salesOrderNumber;
  final String? salesInvoiceId;
  final String conversionStatus;
  final String? convertedAt;
  final String? conversionErrorCode;
  final String idempotencyKey;
  final String createdAt;
  final String updatedAt;
  final bool canCancel;

  const PreorderBooking({
    required this.preorderId,
    required this.userId,
    required this.customerId,
    required this.customerDisplayName,
    required this.productId,
    required this.productNameSnapshot,
    required this.skuSnapshot,
    required this.packingSizeSnapshot,
    this.imageUrlSnapshot,
    required this.quantity,
    required this.onlinePriceSnapshot,
    required this.mrpSnapshot,
    required this.gstPercentageSnapshot,
    required this.totalProductValue,
    required this.paymentOption,
    required this.paymentTypeLabel,
    required this.bookingAdvance,
    double? initialBookingAdvance,
    double? totalVerifiedPaid,
    required this.remainingBalance,
    required this.giftWrap,
    required this.specialSuggestion,
    required this.expectedDeliveryDate,
    required this.preferredCourierAgent,
    this.deliveryAddress,
    this.formattedDeliveryAddress = '',
    required this.currency,
    required this.bookingStatus,
    required this.paymentStatus,
    this.paymentReference,
    this.lastPaymentReference,
    this.checkoutReference,
    this.invoiceId,
    this.salesOrderId,
    this.salesOrderNumber,
    this.salesInvoiceId,
    this.conversionStatus = 'not_applicable',
    this.convertedAt,
    this.conversionErrorCode,
    required this.idempotencyKey,
    required this.createdAt,
    required this.updatedAt,
    required this.canCancel,
  })  : initialBookingAdvance = initialBookingAdvance ?? bookingAdvance,
        totalVerifiedPaid = totalVerifiedPaid ?? bookingAdvance;

  PreorderBookingStatus get status => bookingStatus;

  bool get isConvertedToSalesOrder =>
      conversionStatus == 'converted' ||
      (salesOrderId != null && salesOrderId!.trim().isNotEmpty);

  bool get canPayRemainingBalance =>
      remainingBalance > 0 &&
      bookingStatus != PreorderBookingStatus.cancelled &&
      paymentStatus != PreorderPaymentStatus.paid &&
      !isConvertedToSalesOrder;

  String get conversionStatusLabel {
    if (isConvertedToSalesOrder) {
      return 'Converted to Sales Order (PRE-ORDER)';
    }
    switch (conversionStatus) {
      case 'failed':
        return 'Conversion Pending Reconciliation';
      case 'processing':
      case 'pending':
        return 'Converting to Sales Order...';
      default:
        if (remainingBalance > 0) {
          return 'Awaiting Remaining Balance';
        }
        return 'Not Converted';
    }
  }

  factory PreorderBooking.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toInt() ?? 1;
    final onlinePrice = (json['onlinePriceSnapshot'] as num?)?.toDouble() ??
        (json['unitPriceSnapshot'] as num?)?.toDouble() ??
        0.0;
    final totalVal = (json['totalProductValue'] as num?)?.toDouble() ??
        (json['totalSnapshot'] as num?)?.toDouble() ??
        roundPreorderCurrency(onlinePrice * qty);
    final option = PreorderPaymentOption.fromString(
      json['paymentType']?.toString() ?? json['paymentTypeLabel']?.toString(),
    );
    final advance = (json['bookingAdvance'] as num?)?.toDouble() ?? totalVal;
    final initialAdvance =
        (json['initialBookingAdvance'] as num?)?.toDouble() ?? advance;
    final payStatus = PreorderPaymentStatus.fromString(
      json['paymentStatus']?.toString(),
    );
    final verifiedPaid = (json['totalVerifiedPaid'] as num?)?.toDouble() ??
        (payStatus == PreorderPaymentStatus.paid
            ? totalVal
            : (payStatus == PreorderPaymentStatus.partiallyPaid
                ? advance
                : 0.0));
    final balance = (json['remainingBalance'] as num?)?.toDouble() ??
        roundPreorderCurrency((totalVal - verifiedPaid).clamp(0.0, totalVal));

    PreorderDeliveryAddress? parsedAddress;
    final rawAddr = json['deliveryAddress'] ?? json['shippingAddress'];
    if (rawAddr is Map) {
      final candidate = PreorderDeliveryAddress.fromJson(
        Map<String, dynamic>.from(rawAddr),
      );
      if (candidate.isNotEmpty) {
        parsedAddress = candidate;
      }
    } else {
      final flatCandidate = PreorderDeliveryAddress.fromJson(json);
      if (flatCandidate.isNotEmpty) {
        parsedAddress = flatCandidate;
      }
    }

    final rawSalesOrderId = json['salesOrderId']?.toString();
    final salesOrderIdClean =
        (rawSalesOrderId != null && rawSalesOrderId.trim().isNotEmpty)
            ? rawSalesOrderId.trim()
            : null;
    final rawSalesOrderNumber = json['salesOrderNumber']?.toString();
    final salesOrderNumberClean =
        (rawSalesOrderNumber != null && rawSalesOrderNumber.trim().isNotEmpty)
            ? rawSalesOrderNumber.trim()
            : null;
    final rawSalesInvoiceId = json['salesInvoiceId']?.toString();
    final salesInvoiceIdClean =
        (rawSalesInvoiceId != null && rawSalesInvoiceId.trim().isNotEmpty)
            ? rawSalesInvoiceId.trim()
            : null;
    final rawConversionStatus =
        (json['conversionStatus']?.toString() ?? '').trim().toLowerCase();
    final effectiveConversionStatus = rawConversionStatus.isNotEmpty
        ? rawConversionStatus
        : (salesOrderIdClean != null
            ? 'converted'
            : (payStatus == PreorderPaymentStatus.paid && balance <= 0
                ? 'pending'
                : 'not_applicable'));

    return PreorderBooking(
      preorderId: '${json['preorderId'] ?? ''}',
      userId: '${json['userId'] ?? ''}',
      customerId: '${json['customerId'] ?? ''}',
      customerDisplayName: '${json['customerDisplayName'] ?? ''}',
      productId: '${json['productId'] ?? ''}',
      productNameSnapshot: '${json['productNameSnapshot'] ?? ''}',
      skuSnapshot: '${json['skuSnapshot'] ?? ''}',
      packingSizeSnapshot: '${json['packingSizeSnapshot'] ?? ''}',
      imageUrlSnapshot: json['imageUrlSnapshot']?.toString(),
      quantity: qty,
      onlinePriceSnapshot: onlinePrice,
      mrpSnapshot: (json['mrpSnapshot'] as num?)?.toDouble() ?? onlinePrice,
      gstPercentageSnapshot:
          (json['gstPercentageSnapshot'] as num?)?.toDouble() ?? 0.0,
      totalProductValue: totalVal,
      paymentOption: option,
      paymentTypeLabel:
          json['paymentTypeLabel']?.toString() ?? option.displayLabel,
      bookingAdvance: advance,
      initialBookingAdvance: initialAdvance,
      totalVerifiedPaid: verifiedPaid,
      remainingBalance: balance,
      giftWrap: json['giftWrap'] == true,
      specialSuggestion:
          '${json['specialSuggestion'] ?? json['notes'] ?? ''}',
      expectedDeliveryDate:
          '${json['expectedDeliveryDate'] ?? json['dateLocalSnapshot'] ?? ''}',
      preferredCourierAgent:
          '${json['preferredCourierAgent'] ?? 'India Post'}',
      deliveryAddress: parsedAddress,
      formattedDeliveryAddress: parsedAddress?.displaySummary ??
          '${json['formattedDeliveryAddress'] ?? ''}',
      currency: '${json['currency'] ?? 'INR'}',
      bookingStatus: PreorderBookingStatus.fromString(
        json['bookingStatus']?.toString() ?? json['status']?.toString(),
      ),
      paymentStatus: payStatus,
      paymentReference: json['paymentReference']?.toString(),
      lastPaymentReference: json['lastPaymentReference']?.toString(),
      checkoutReference: json['checkoutReference']?.toString(),
      invoiceId: json['invoiceId']?.toString(),
      salesOrderId: salesOrderIdClean,
      salesOrderNumber: salesOrderNumberClean,
      salesInvoiceId: salesInvoiceIdClean,
      conversionStatus: effectiveConversionStatus,
      convertedAt: json['convertedAt']?.toString(),
      conversionErrorCode: json['conversionErrorCode']?.toString(),
      idempotencyKey: '${json['idempotencyKey'] ?? ''}',
      createdAt: '${json['createdAt'] ?? ''}',
      updatedAt: '${json['updatedAt'] ?? ''}',
      canCancel: json['canCancel'] == true,
    );
  }
}

class PreorderBalanceCheckoutQuote {
  final String preorderId;
  final String checkoutId;
  final double payableAmount;
  final double totalProductValue;
  final double initialBookingAdvance;
  final double totalVerifiedPaid;
  final double remainingBalance;
  final String currency;
  final Map<String, dynamic> orderData;

  const PreorderBalanceCheckoutQuote({
    required this.preorderId,
    required this.checkoutId,
    required this.payableAmount,
    required this.totalProductValue,
    required this.initialBookingAdvance,
    required this.totalVerifiedPaid,
    required this.remainingBalance,
    required this.currency,
    required this.orderData,
  });

  factory PreorderBalanceCheckoutQuote.fromJson(Map<String, dynamic> json) {
    final payable = (json['payableAmount'] as num?)?.toDouble() ??
        (json['remainingBalance'] as num?)?.toDouble() ??
        0.0;
    return PreorderBalanceCheckoutQuote(
      preorderId: '${json['preorderId'] ?? ''}',
      checkoutId: '${json['checkoutId'] ?? ''}',
      payableAmount: payable,
      totalProductValue:
          (json['totalProductValue'] as num?)?.toDouble() ?? payable,
      initialBookingAdvance:
          (json['initialBookingAdvance'] as num?)?.toDouble() ?? 0.0,
      totalVerifiedPaid:
          (json['totalVerifiedPaid'] as num?)?.toDouble() ?? 0.0,
      remainingBalance:
          (json['remainingBalance'] as num?)?.toDouble() ?? payable,
      currency: '${json['currency'] ?? 'INR'}',
      orderData: json['orderData'] is Map
          ? Map<String, dynamic>.from(json['orderData'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class PreorderPagedResult<T> {
  final List<T> items;
  final String? nextCursor;
  final int? total;

  const PreorderPagedResult({
    required this.items,
    this.nextCursor,
    this.total,
  });
}
