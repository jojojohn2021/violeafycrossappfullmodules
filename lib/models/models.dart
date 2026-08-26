import '../core/config/env_config.dart';

// --- USER & PERMISSIONS ---
class User {
  final String id;
  final String name;
  final String role; // 'Admin' | 'Sales' | 'Marketing' | 'Support' | 'Referral Team'
  final String email;
  final String avatar;
  final String team;
  final String? mobileNumber;
  final String? password;

  User({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    required this.avatar,
    required this.team,
    this.mobileNumber,
    this.password,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    role: json['role'] ?? 'Referral Team',
    email: json['email'] ?? '',
    avatar: EnvConfig.normalizeUrl(json['avatar'] ?? ''),
    team: json['team'] ?? '',
    mobileNumber: json['mobileNumber'],
    password: json['password'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'email': email,
    'avatar': avatar,
    'team': team,
    'mobileNumber': mobileNumber,
    'password': password,
  };
}

class Permission {
  final String module;
  final bool read;
  final bool create;
  final bool edit;
  final bool delete;

  Permission({
    required this.module,
    required this.read,
    required this.create,
    required this.edit,
    required this.delete,
  });

  factory Permission.fromJson(Map<String, dynamic> json) => Permission(
    module: json['module'] ?? '',
    read: json['read'] ?? false,
    create: json['create'] ?? false,
    edit: json['edit'] ?? false,
    delete: json['delete'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'module': module,
    'read': read,
    'create': create,
    'edit': edit,
    'delete': delete,
  };
}

// --- LEADS ---
class Lead {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String countrymobilecode;
  final String mobilenumberwithcountrycode;
  final String status; // 'New' | 'Contacted' | 'Qualified' | 'Proposal' | 'Nurturing' | 'Unqualified'
  final double score;
  final String source;
  final String assignedTo;
  final String createdAt;
  final double value;
  final String? referralCode;
  final String? referralPartner;
  final String? referralmobileno;
  final String? pincode;
  final String? productId;

  Lead({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.countrymobilecode = '+91',
    this.mobilenumberwithcountrycode = '',
    required this.status,
    required this.score,
    required this.source,
    required this.assignedTo,
    required this.createdAt,
    required this.value,
    this.referralCode,
    this.referralPartner,
    this.referralmobileno,
    this.pincode,
    this.productId,
  });

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    email: json['email'] ?? '',
    phone: json['phone'] ?? '',
    countrymobilecode: json['countrymobilecode'] ?? json['countryMobileCode'] ?? '+91',
    mobilenumberwithcountrycode: json['mobilenumberwithcountrycode'] ?? json['mobileNumberWithCountryCode'] ?? (json['phone'] != null && json['phone'].toString().isNotEmpty ? (json['phone'].toString().startsWith('+') ? json['phone'] : '${json['countrymobilecode'] ?? json['countryMobileCode'] ?? '+91'}${json['phone']}') : ''),
    status: json['status'] ?? 'New',
    score: (json['score'] ?? 0).toDouble(),
    source: json['source'] ?? '',
    assignedTo: json['assignedTo'] ?? '',
    createdAt: json['createdAt'] ?? '',
    value: (json['value'] ?? 0).toDouble(),
    referralCode: json['referralCode'] ?? json['referralcode'],
    referralPartner: json['referralPartner'] ?? json['referralpartner'],
    referralmobileno: json['referralmobileno'] ?? json['referralMobileNo'],
    pincode: json['pincode'],
    productId: json['productId'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'countrymobilecode': countrymobilecode,
    'mobilenumberwithcountrycode': mobilenumberwithcountrycode.isNotEmpty ? mobilenumberwithcountrycode : (phone.startsWith('+') ? phone : '$countrymobilecode$phone'),
    'status': status,
    'score': score,
    'source': source,
    'assignedTo': assignedTo,
    'createdAt': createdAt,
    'value': value,
    'referralCode': referralCode,
    'referralPartner': referralPartner,
    'referralmobileno': referralmobileno,
    'pincode': pincode,
    'productId': productId,
  };
}

// --- TASKS & EVENTS ---
class Task {
  final String id;
  final String title;
  final String description;
  final String dueDate;
  final String priority; // 'Low' | 'Medium' | 'High'
  final String status; // 'Pending' | 'Completed'
  final String assignedTo;
  final String category; // 'Call' | 'Email' | 'Meeting' | 'Demo' | 'Task'
  final Map<String, dynamic>? linkedTo;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.priority,
    required this.status,
    required this.assignedTo,
    required this.category,
    this.linkedTo,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    dueDate: json['dueDate'] ?? '',
    priority: json['priority'] ?? 'Medium',
    status: json['status'] ?? 'Pending',
    assignedTo: json['assignedTo'] ?? '',
    category: json['category'] ?? 'Task',
    linkedTo: json['linkedTo'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dueDate': dueDate,
    'priority': priority,
    'status': status,
    'assignedTo': assignedTo,
    'category': category,
    'linkedTo': linkedTo,
  };
}

class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final String start;
  final String end;
  final String type; // 'Meeting' | 'Demo' | 'FollowUp' | 'CampaignRun'
  final String color;
  final String? linkedTo;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    required this.type,
    required this.color,
    this.linkedTo,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    start: json['start'] ?? '',
    end: json['end'] ?? '',
    type: json['type'] ?? 'Meeting',
    color: json['color'] ?? '#747ff1',
    linkedTo: json['linkedTo'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'start': start,
    'end': end,
    'type': type,
    'color': color,
    'linkedTo': linkedTo,
  };
}

// --- PRODUCTS ---
class ProductPerformance {
  final String id;
  final String name;
  final String sku;
  final String packingSize;
  final String unit;
  final double onlinePrice;
  final double shopPrice;
  final String notes;
  final String? imageUrl; // Firebase Storage or HTTP URL
  final int unitsSold;
  final double revenue;
  final double growthRate;
  final int stock;
  final double amazonSales;
  final double flipkartSales;
  final double meeshoSales;
  final double vamjoSales;
  final double whatsappSales;
  final double countersaleSales;
  final double? gstPercentage;
  final int? stockIn;
  final int? stockOut;
  final String? vamjoWeblink;
  final String? amazonWeblink;
  final String? flipkartWeblink;
  final String? meeshoWeblink;
  final String? category;
  final String? brand;
  final String? brandOwner;
  final List<String>? images;
  final String? description;
  final String? ingredients;
  final String? specifications;
  final String? variants;
  final String? stockAvailability;
  final double? offerPrice;
  final double? mrp;
  final double? discount;
  final double? rating;
  final int? reviewsCount;
  final List<String>? videos;

  ProductPerformance({
    required this.id,
    required this.name,
    required this.sku,
    required this.packingSize,
    required this.unit,
    required this.onlinePrice,
    required this.shopPrice,
    required this.notes,
    this.imageUrl,
    required this.unitsSold,
    required this.revenue,
    required this.growthRate,
    required this.stock,
    required this.amazonSales,
    required this.flipkartSales,
    required this.meeshoSales,
    required this.vamjoSales,
    required this.whatsappSales,
    required this.countersaleSales,
    this.gstPercentage,
    this.stockIn,
    this.stockOut,
    this.vamjoWeblink,
    this.amazonWeblink,
    this.flipkartWeblink,
    this.meeshoWeblink,
    this.category,
    this.brand,
    this.brandOwner,
    this.images,
    this.description,
    this.ingredients,
    this.specifications,
    this.variants,
    this.stockAvailability,
    this.offerPrice,
    this.mrp,
    this.discount,
    this.rating,
    this.reviewsCount,
    this.videos,
  });

  factory ProductPerformance.fromJson(Map<String, dynamic> json) => ProductPerformance(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    sku: json['sku'] ?? '',
    packingSize: json['packingSize'] ?? '',
    unit: json['unit'] ?? '',
    onlinePrice: (json['onlinePrice'] ?? 0).toDouble(),
    shopPrice: (json['shopPrice'] ?? 0).toDouble(),
    notes: json['notes'] ?? '',
    imageUrl: (json['imageUrl'] ?? json['image'])?.toString() != null 
        ? EnvConfig.normalizeUrl((json['imageUrl'] ?? json['image']).toString()) 
        : null,
    unitsSold: (json['unitsSold'] ?? 0).toInt(),
    revenue: (json['revenue'] ?? 0).toDouble(),
    growthRate: (json['growthRate'] ?? 0).toDouble(),
    stock: (json['stock'] ?? 0).toInt(),
    amazonSales: (json['amazonSales'] ?? 0).toDouble(),
    flipkartSales: (json['flipkartSales'] ?? 0).toDouble(),
    meeshoSales: (json['meeshoSales'] ?? 0).toDouble(),
    vamjoSales: (json['vamjoSales'] ?? 0).toDouble(),
    whatsappSales: (json['whatsappSales'] ?? 0).toDouble(),
    countersaleSales: (json['countersaleSales'] ?? 0).toDouble(),
    gstPercentage: json['gstPercentage'] != null ? (json['gstPercentage']).toDouble() : null,
    stockIn: json['stockIn'] != null ? (json['stockIn']).toInt() : null,
    stockOut: json['stockOut'] != null ? (json['stockOut']).toInt() : null,
    vamjoWeblink: json['vamjoWeblink'],
    amazonWeblink: json['amazonWeblink'],
    flipkartWeblink: json['flipkartWeblink'],
    meeshoWeblink: json['meeshoWeblink'],
    category: json['category'],
    brand: json['brand'],
    brandOwner: json['brandOwner'],
    images: json['images'] != null ? (json['images'] as List).map((e) => EnvConfig.normalizeUrl(e.toString())).toList() : null,
    description: json['description'],
    ingredients: json['ingredients'],
    specifications: json['specifications'],
    variants: json['variants'],
    stockAvailability: json['stockAvailability'],
    offerPrice: json['offerPrice'] != null ? (json['offerPrice']).toDouble() : null,
    mrp: json['mrp'] != null ? (json['mrp']).toDouble() : null,
    discount: json['discount'] != null ? (json['discount']).toDouble() : null,
    rating: json['rating'] != null ? (json['rating']).toDouble() : null,
    reviewsCount: json['reviewsCount'] != null ? (json['reviewsCount']).toInt() : null,
    videos: json['videos'] != null ? List<String>.from(json['videos']) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sku': sku,
    'packingSize': packingSize,
    'unit': unit,
    'onlinePrice': onlinePrice,
    'shopPrice': shopPrice,
    'notes': notes,
    'imageUrl': imageUrl,
    'unitsSold': unitsSold,
    'revenue': revenue,
    'growthRate': growthRate,
    'stock': stock,
    'amazonSales': amazonSales,
    'flipkartSales': flipkartSales,
    'meeshoSales': meeshoSales,
    'vamjoSales': vamjoSales,
    'whatsappSales': whatsappSales,
    'countersaleSales': countersaleSales,
    'gstPercentage': gstPercentage,
    'stockIn': stockIn,
    'stockOut': stockOut,
    'vamjoWeblink': vamjoWeblink,
    'amazonWeblink': amazonWeblink,
    'flipkartWeblink': flipkartWeblink,
    'meeshoWeblink': meeshoWeblink,
    'category': category,
    'brand': brand,
    'brandOwner': brandOwner,
    'images': images,
    'description': description,
    'ingredients': ingredients,
    'specifications': specifications,
    'variants': variants,
    'stockAvailability': stockAvailability,
    'offerPrice': offerPrice,
    'mrp': mrp,
    'discount': discount,
    'rating': rating,
    'reviewsCount': reviewsCount,
    'videos': videos,
  };
}

// --- CUSTOMERS ---
class CustomerPerformance {
  final String id;
  final String? authUid;
  final String name;
  final String company;
  final String email;
  final String mobileNumber;
  final String countrymobilecode;
  final String mobilenumberwithcountrycode;
  final String address;
  final String state;
  final String district;
  final String? pincode;
  final double totalSpent;
  final int dealsClosed;
  final double satisfactionScore;
  final String lastOrderDate;
  final String tier; // 'Platinum' | 'Gold' | 'Silver' | 'Bronze'
  final String? partnerName;
  final bool? isFromLead;
  final String? leadId;
  final String? referralCode;
  final String? referralPartner;
  final String? password;

  CustomerPerformance({
    required this.id,
    this.authUid,
    required this.name,
    required this.company,
    required this.email,
    required this.mobileNumber,
    this.countrymobilecode = '+91',
    this.mobilenumberwithcountrycode = '',
    required this.address,
    required this.state,
    required this.district,
    this.pincode,
    required this.totalSpent,
    required this.dealsClosed,
    required this.satisfactionScore,
    required this.lastOrderDate,
    required this.tier,
    this.partnerName,
    this.isFromLead,
    this.leadId,
    this.referralCode,
    this.referralPartner,
    this.password,
  });

  factory CustomerPerformance.fromJson(Map<String, dynamic> json) => CustomerPerformance(
    id: json['customerId'] ?? json['id'] ?? '',
    authUid: json['authUid'],
    name: json['name'] ?? '',
    company: json['company'] ?? '',
    email: json['email'] ?? '',
    mobileNumber: json['mobileNumber'] ?? '',
    countrymobilecode: json['countrymobilecode'] ?? json['countryMobileCode'] ?? '+91',
    mobilenumberwithcountrycode: json['mobilenumberwithcountrycode'] ?? json['mobileNumberWithCountryCode'] ?? (json['mobileNumber'] != null && json['mobileNumber'].toString().isNotEmpty ? (json['mobileNumber'].toString().startsWith('+') ? json['mobileNumber'] : '${json['countrymobilecode'] ?? json['countryMobileCode'] ?? '+91'}${json['mobileNumber']}') : ''),
    address: json['address'] ?? '',
    state: json['state'] ?? '',
    district: json['district'] ?? '',
    pincode: json['pincode'],
    totalSpent: (json['totalSpent'] ?? 0).toDouble(),
    dealsClosed: (json['dealsClosed'] ?? 0).toInt(),
    satisfactionScore: (json['satisfactionScore'] ?? 0).toDouble(),
    lastOrderDate: json['lastOrderDate'] ?? '',
    tier: json['tier'] ?? 'Bronze',
    partnerName: json['partnerName'],
    isFromLead: json['isFromLead'],
    leadId: json['leadId'],
    referralCode: json['referralcode'] ?? json['referralCode'],
    referralPartner: json['referralpartner'] ?? json['referralPartner'],
    password: json['password'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerId': id,
    'authUid': authUid,
    'name': name,
    'company': company,
    'email': email,
    'mobileNumber': mobileNumber,
    'countrymobilecode': countrymobilecode,
    'mobilenumberwithcountrycode': mobilenumberwithcountrycode.isNotEmpty ? mobilenumberwithcountrycode : (mobileNumber.startsWith('+') ? mobileNumber : '$countrymobilecode$mobileNumber'),
    'address': address,
    'state': state,
    'district': district,
    'pincode': pincode,
    'totalSpent': totalSpent,
    'dealsClosed': dealsClosed,
    'satisfactionScore': satisfactionScore,
    'lastOrderDate': lastOrderDate,
    'tier': tier,
    'partnerName': partnerName,
    'isFromLead': isFromLead,
    'leadId': leadId,
    'leadslinkid': leadId,
    'referralCode': referralCode,
    'referralcode': referralCode,
    'referralpartner': referralPartner ?? partnerName,
    'password': password,
  };
}

// --- SALES ORDERS & CHECKOUT ---
class SalesProduct {
  final String productId;
  final String productName;
  final String? imageUrl;
  final int quantity;
  final double price;
  final double? gstPercentage;
  final String? category;
  final String? brand;
  final String? brandOwner;

  SalesProduct({
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.quantity,
    required this.price,
    this.gstPercentage,
    this.category,
    this.brand,
    this.brandOwner,
  });

  factory SalesProduct.fromJson(Map<String, dynamic> json) => SalesProduct(
    productId: json['productId'] ?? '',
    productName: json['productName'] ?? '',
    imageUrl: json['imageUrl']?.toString(),
    quantity: (json['quantity'] ?? 0).toInt(),
    price: (json['price'] ?? 0).toDouble(),
    gstPercentage: json['gstPercentage'] != null ? (json['gstPercentage']).toDouble() : null,
    category: json['category'],
    brand: json['brand'],
    brandOwner: json['brandOwner'],
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'imageUrl': imageUrl,
    'quantity': quantity,
    'price': price,
    'gstPercentage': gstPercentage,
    'category': category,
    'brand': brand,
    'brandOwner': brandOwner,
  };
}

class SalesOrder {
  final String id;
  final String orderNumber;
  final String customerId;
  final String customerName;
  final String customerCompany;
  final List<SalesProduct> products;
  final double totalValue;
  final String paymentStatus; // 'Paid' | 'Pending' | 'Overdue' | 'Refunded'
  final String deliveryStatus; // 'Pending' | 'Shipped' | 'Delivered' | 'Cancelled'
  final String assignedTo;
  final String createdAt;
  final String paymentMethod; // 'Cash' | 'Bank Transfer' | 'Stripe' | 'UPI' | 'Credit Card'
  final String? invoiceDate;
  final String? pickupDate;
  final String? courierAgency;
  final double? courierCharges;
  final String? contactNo;
  final String? referralCode;
  final String? orderType; // 'Online' | 'Shop'
  final String? salesChannel;
  final String? customerEmail;
  final String? customerMobile;
  final CustomerDeliveryAddress? shippingAddress;

  SalesOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.customerCompany,
    required this.products,
    required this.totalValue,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.assignedTo,
    required this.createdAt,
    required this.paymentMethod,
    this.invoiceDate,
    this.pickupDate,
    this.courierAgency,
    this.courierCharges,
    this.contactNo,
    this.referralCode,
    this.orderType,
    this.salesChannel,
    this.customerEmail,
    this.customerMobile,
    this.shippingAddress,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) => SalesOrder(
    id: json['id'] ?? '',
    orderNumber: json['orderNumber'] ?? '',
    customerId: json['customerId'] ?? '',
    customerName: json['customerName'] ?? '',
    customerCompany: json['customerCompany'] ?? '',
    products: json['products'] != null 
      ? (json['products'] as List).map((i) => SalesProduct.fromJson(i)).toList()
      : [],
    totalValue: (json['totalValue'] ?? 0).toDouble(),
    paymentStatus: json['paymentStatus'] ?? 'Pending',
    deliveryStatus: json['deliveryStatus'] ?? 'Pending',
    assignedTo: json['assignedTo'] ?? '',
    createdAt: json['createdAt'] ?? '',
    paymentMethod: json['paymentMethod'] ?? 'COD',
    invoiceDate: json['invoiceDate'],
    pickupDate: json['pickupDate'],
    courierAgency: json['courierAgency'],
    courierCharges: json['courierCharges'] != null ? (json['courierCharges']).toDouble() : null,
    contactNo: json['contactNo'],
    referralCode: json['referralCode'],
    orderType: json['orderType'],
    salesChannel: json['salesChannel'],
    customerEmail: json['customerEmail'],
    customerMobile: json['customerMobile'],
    shippingAddress: json['shippingAddress'] is Map
      ? CustomerDeliveryAddress.fromJson(Map<String, dynamic>.from(json['shippingAddress']))
      : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderNumber': orderNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerCompany': customerCompany,
    'products': products.map((i) => i.toJson()).toList(),
    'totalValue': totalValue,
    'paymentStatus': paymentStatus,
    'deliveryStatus': deliveryStatus,
    'assignedTo': assignedTo,
    'createdAt': createdAt,
    'paymentMethod': paymentMethod,
    'invoiceDate': invoiceDate,
    'pickupDate': pickupDate,
    'courierAgency': courierAgency,
    'courierCharges': courierCharges,
    'contactNo': contactNo,
    'referralCode': referralCode,
    'orderType': orderType,
    'salesChannel': salesChannel,
    'customerEmail': customerEmail,
    'customerMobile': customerMobile,
    'shippingAddress': shippingAddress?.toJson(),
  };
}


// --- PAYOUTS & WALLET ---
class PartnerPayout {
  final String id;
  final String partnerId;
  final String partnerName;
  final String partnerMobile;
  final double amount;
  final String paymentMethod; // 'Cash' | 'Bank Transfer' | 'UPI' | 'Cheque'
  final String payoutDate;
  final String? notes;
  final String? referenceNumber;
  final String status; // 'Draft' | 'Pending Approval' | 'Approved' | 'Processing' | 'Paid' | 'Rejected' | 'Settled'
  final String? approvedBy;
  final String? approvedDate;
  final String? rejectionReason;
  final String? paidDate;

  PartnerPayout({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.partnerMobile,
    required this.amount,
    required this.paymentMethod,
    required this.payoutDate,
    this.notes,
    this.referenceNumber,
    required this.status,
    this.approvedBy,
    this.approvedDate,
    this.rejectionReason,
    this.paidDate,
  });

  factory PartnerPayout.fromJson(Map<String, dynamic> json) => PartnerPayout(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    partnerName: json['partnerName'] ?? '',
    partnerMobile: json['partnerMobile'] ?? '',
    amount: (json['amount'] ?? 0).toDouble(),
    paymentMethod: json['paymentMethod'] ?? 'UPI',
    payoutDate: json['payoutDate'] ?? '',
    notes: json['notes'],
    referenceNumber: json['referenceNumber'],
    status: json['status'] ?? 'Draft',
    approvedBy: json['approvedBy'],
    approvedDate: json['approvedDate'],
    rejectionReason: json['rejectionReason'],
    paidDate: json['paidDate'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'partnerName': partnerName,
    'partnerMobile': partnerMobile,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'payoutDate': payoutDate,
    'notes': notes,
    'referenceNumber': referenceNumber,
    'status': status,
    'approvedBy': approvedBy,
    'approvedDate': approvedDate,
    'rejectionReason': rejectionReason,
    'paidDate': paidDate,
  };
}

class Wallet {
  final String id;
  final String partnerId;
  final double totalBalance;
  final double availableBalance;
  final double pendingApprovalAmount;
  final double processingAmount;
  final double paidAmount;

  Wallet({
    required this.id,
    required this.partnerId,
    required this.totalBalance,
    required this.availableBalance,
    required this.pendingApprovalAmount,
    required this.processingAmount,
    required this.paidAmount,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    totalBalance: (json['totalBalance'] ?? 0).toDouble(),
    availableBalance: (json['availableBalance'] ?? 0).toDouble(),
    pendingApprovalAmount: (json['pendingApprovalAmount'] ?? 0).toDouble(),
    processingAmount: (json['processingAmount'] ?? 0).toDouble(),
    paidAmount: (json['paidAmount'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'totalBalance': totalBalance,
    'availableBalance': availableBalance,
    'pendingApprovalAmount': pendingApprovalAmount,
    'processingAmount': processingAmount,
    'paidAmount': paidAmount,
  };
}

class WalletLedger {
  final String id;
  final String partnerId;
  final String transactionType; // 'Credit' | 'Debit'
  final double amount;
  final String referenceType; // 'Commission' | 'Payout'
  final String referenceId;
  final String createdDate;

  WalletLedger({
    required this.id,
    required this.partnerId,
    required this.transactionType,
    required this.amount,
    required this.referenceType,
    required this.referenceId,
    required this.createdDate,
  });

  factory WalletLedger.fromJson(Map<String, dynamic> json) => WalletLedger(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    transactionType: json['transactionType'] ?? 'Credit',
    amount: (json['amount'] ?? 0).toDouble(),
    referenceType: json['referenceType'] ?? 'Commission',
    referenceId: json['referenceId'] ?? '',
    createdDate: json['createdDate'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'transactionType': transactionType,
    'amount': amount,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'createdDate': createdDate,
  };
}

class PayoutNotification {
  final String id;
  final String partnerId;
  final String title;
  final String message;
  final String type; // 'info' | 'success' | 'warning' | 'error'
  final String timestamp;
  final bool isRead;

  PayoutNotification({
    required this.id,
    required this.partnerId,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.isRead,
  });

  factory PayoutNotification.fromJson(Map<String, dynamic> json) => PayoutNotification(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    title: json['title'] ?? '',
    message: json['message'] ?? '',
    type: json['type'] ?? 'info',
    timestamp: json['timestamp'] ?? '',
    isRead: json['isRead'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'title': title,
    'message': message,
    'type': type,
    'timestamp': timestamp,
    'isRead': isRead,
  };
}

// --- SHOPPING COMPONENT EXTENSIONS ---
class ShoppingCartItem {
  final String id;
  final String userId;
  final String productId;
  final int quantity;
  final bool? savedForLater;

  ShoppingCartItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    this.savedForLater,
  });

  factory ShoppingCartItem.fromJson(Map<String, dynamic> json) => ShoppingCartItem(
    id: json['id'] ?? '',
    userId: json['userId'] ?? '',
    productId: json['productId'] ?? '',
    quantity: (json['quantity'] ?? 1).toInt(),
    savedForLater: json['savedForLater'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'productId': productId,
    'quantity': quantity,
    'savedForLater': savedForLater,
  };
}

class WishlistItem {
  final String id;
  final String userId;
  final String productId;
  final String createdAt;

  WishlistItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.createdAt,
  });

  factory WishlistItem.fromJson(Map<String, dynamic> json) => WishlistItem(
    id: json['id'] ?? '',
    userId: json['userId'] ?? '',
    productId: json['productId'] ?? '',
    createdAt: json['createdAt'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'productId': productId,
    'createdAt': createdAt,
  };
}

typedef CustomerAddress = CustomerDeliveryAddress;

class CustomerDeliveryAddress {
  final String id;
  final String userId;
  final String customerId;
  final String name;
  final String mobileNumber;
  final String email;
  final String addressLine;
  final String city;
  final String district;
  final String state;
  final String pincode;
  final bool isDefault;

  CustomerDeliveryAddress({
    required this.id,
    this.userId = '',
    this.customerId = '',
    required this.name,
    required this.mobileNumber,
    this.email = '',
    required this.addressLine,
    required this.city,
    required this.district,
    required this.state,
    required this.pincode,
    required this.isDefault,
  });

  factory CustomerDeliveryAddress.fromJson(Map<String, dynamic> json) => CustomerDeliveryAddress(
    id: json['id'] ?? '',
    userId: json['userId'] ?? json['customerId'] ?? json['mobileNumber'] ?? '',
    customerId: json['customerId'] ?? json['userId'] ?? '',
    name: json['name'] ?? '',
    mobileNumber: json['mobileNumber'] ?? json['userId'] ?? '',
    email: json['email'] ?? '',
    addressLine: json['addressLine'] ?? '',
    city: json['city'] ?? '',
    district: json['district'] ?? '',
    state: json['state'] ?? '',
    pincode: json['pincode'] ?? '',
    isDefault: json['isDefault'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId.isNotEmpty ? userId : mobileNumber,
    'customerId': customerId.isNotEmpty ? customerId : userId,
    'name': name,
    'mobileNumber': mobileNumber,
    'email': email,
    'addressLine': addressLine,
    'city': city,
    'district': district,
    'state': state,
    'pincode': pincode,
    'isDefault': isDefault,
  };
}

class Coupon {
  final String id;
  final String code;
  final String type; // 'percentage' | 'fixed' | 'free_shipping'
  final double value;
  final double? minOrderValue;
  final double? maxDiscount;
  final bool isActive;
  final String expiryDate;
  final String description;

  Coupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    this.minOrderValue,
    this.maxDiscount,
    required this.isActive,
    required this.expiryDate,
    required this.description,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
    id: json['id'] ?? '',
    code: json['code'] ?? '',
    type: json['type'] ?? 'percentage',
    value: (json['value'] ?? 0).toDouble(),
    minOrderValue: json['minOrderValue'] != null ? (json['minOrderValue']).toDouble() : null,
    maxDiscount: json['maxDiscount'] != null ? (json['maxDiscount']).toDouble() : null,
    isActive: json['isActive'] ?? false,
    expiryDate: json['expiryDate'] ?? '',
    description: json['description'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'type': type,
    'value': value,
    'minOrderValue': minOrderValue,
    'maxDiscount': maxDiscount,
    'isActive': isActive,
    'expiryDate': expiryDate,
    'description': description,
  };
}

// --- BRAND CONFIGURATION ---
class BannerConfig {
  final String id;
  final String title;
  final String subtitle;
  final String tag;
  final String? imageUrl;
  final String? bg;

  BannerConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tag,
    this.imageUrl,
    this.bg,
  });

  factory BannerConfig.fromJson(Map<String, dynamic> json) => BannerConfig(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    subtitle: json['subtitle'] ?? '',
    tag: json['tag'] ?? '',
    imageUrl: json['imageUrl'],
    bg: json['bg'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'tag': tag,
    'imageUrl': imageUrl,
    'bg': bg,
  };
}

class BrandConfig {
  final String logoType; // 'fruits_flowers' | 'apps_grid' | 'initial' | 'custom_url'
  final String? logoUrl;
  final String imageUrl;
  final String imageType; // 'preset' | 'custom_url' | 'uploaded'
  final String brandName;
  final String brandTagline;
  final String welcomeHeader;
  final String layoutStyle; // 'split' | 'backdrop' | 'compact'
  final int overlayOpacity;
  final List<BannerConfig>? banners;

  BrandConfig({
    required this.logoType,
    this.logoUrl,
    required this.imageUrl,
    required this.imageType,
    required this.brandName,
    required this.brandTagline,
    required this.welcomeHeader,
    required this.layoutStyle,
    required this.overlayOpacity,
    this.banners,
  });

  factory BrandConfig.fromJson(Map<String, dynamic> json) => BrandConfig(
    logoType: json['logoType'] ?? 'fruits_flowers',
    logoUrl: json['logoUrl'],
    imageUrl: json['imageUrl'] ?? '',
    imageType: json['imageType'] ?? 'preset',
    brandName: json['brandName'] ?? 'Fruits n Flowers',
    brandTagline: json['brandTagline'] ?? '',
    welcomeHeader: json['welcomeHeader'] ?? 'Welcome',
    layoutStyle: json['layoutStyle'] ?? 'split',
    overlayOpacity: (json['overlayOpacity'] ?? 45).toInt(),
    banners: json['banners'] != null
      ? (json['banners'] as List).map((b) => BannerConfig.fromJson(b)).toList()
      : [],
  );

  Map<String, dynamic> toJson() => {
    'logoType': logoType,
    'logoUrl': logoUrl,
    'imageUrl': imageUrl,
    'imageType': imageType,
    'brandName': brandName,
    'brandTagline': brandTagline,
    'welcomeHeader': welcomeHeader,
    'layoutStyle': layoutStyle,
    'overlayOpacity': overlayOpacity,
    'banners': banners?.map((b) => b.toJson()).toList(),
  };
}

// --- PAYMENTS & TRANSACTION LOGS ---
class PaymentTransaction {
  final String id;
  final String orderId;
  final double amount;
  final String paymentMethod;
  final String gateway;
  final String paymentGateway;
  final String paymentAggregator;
  final String customerMobile;
  final String customerAddress;
  final String customerName;
  final String customerEmail;
  String status; // 'Initiated' | 'Success' | 'Failed' | 'Cancelled'
  final String transactionReference;
  final String environment;
  String? errorMessage;
  final String createdAt;
  String updatedAt;
  final List<Map<String, dynamic>> statusHistory;
  final List<Map<String, dynamic>> logs;

  PaymentTransaction({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.paymentMethod,
    required this.gateway,
    required this.paymentGateway,
    required this.paymentAggregator,
    required this.customerMobile,
    required this.customerAddress,
    required this.customerName,
    required this.customerEmail,
    required this.status,
    required this.transactionReference,
    required this.environment,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.statusHistory,
    required this.logs,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    final gatewayVal = json['paymentGateway'] ?? json['gateway'] ?? json['paymentAggregator'] ?? json['aggregator'] ?? 'PayU';
    final mobileVal = json['customerMobile'] ?? json['customerPhone'] ?? json['phone'] ?? json['orderPayload']?['customerMobile'] ?? json['orderPayload']?['shippingAddress']?['mobileNumber'] ?? '';
    final addressVal = json['customerAddress'] ?? json['deliveryAddress'] ?? json['address'] ?? json['orderPayload']?['customerAddress'] ?? '';
    final nameVal = json['customerName'] ?? json['orderPayload']?['customerName'] ?? 'Leafy Shopper';
    final emailVal = json['customerEmail'] ?? json['orderPayload']?['customerEmail'] ?? '';

    return PaymentTransaction(
      id: json['id'] ?? '',
      orderId: json['orderId'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      paymentMethod: json['paymentMethod'] ?? 'Credit Card',
      gateway: gatewayVal,
      paymentGateway: gatewayVal,
      paymentAggregator: gatewayVal,
      customerMobile: mobileVal.toString(),
      customerAddress: addressVal.toString(),
      customerName: nameVal.toString(),
      customerEmail: emailVal.toString(),
      status: json['status'] ?? 'Initiated',
      transactionReference: json['transactionReference'] ?? '',
      environment: json['environment'] ?? 'Test',
      errorMessage: json['errorMessage'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
      statusHistory: json['statusHistory'] != null 
        ? List<Map<String, dynamic>>.from(json['statusHistory']) 
        : [],
      logs: json['logs'] != null 
        ? List<Map<String, dynamic>>.from(json['logs']) 
        : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'gateway': gateway,
    'paymentGateway': paymentGateway,
    'paymentAggregator': paymentAggregator,
    'customerMobile': customerMobile,
    'customerAddress': customerAddress,
    'customerName': customerName,
    'customerEmail': customerEmail,
    'status': status,
    'transactionReference': transactionReference,
    'environment': environment,
    'errorMessage': errorMessage,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'statusHistory': statusHistory,
    'logs': logs,
  };
}

class ProductReview {
  final String id;
  final String productId;
  final String userId;
  final String userName;
  final double rating;
  final String comment;
  final String createdAt;

  ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
    id: json['id'] ?? '',
    productId: json['productId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? '',
    rating: (json['rating'] ?? 5.0).toDouble(),
    comment: json['comment'] ?? '',
    createdAt: json['createdAt'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'userId': userId,
    'userName': userName,
    'rating': rating,
    'comment': comment,
    'createdAt': createdAt,
  };
}

// --- REFERRAL & PERFORMANCE EXTENSIONS ---
class CommissionTransaction {
  final String id;
  final String partnerId;
  final String commissionType; // e.g. 'Referral Commission'
  final double commissionAmount;
  final String transactionDate;

  CommissionTransaction({
    required this.id,
    required this.partnerId,
    required this.commissionType,
    required this.commissionAmount,
    required this.transactionDate,
  });

  factory CommissionTransaction.fromJson(Map<String, dynamic> json) => CommissionTransaction(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    commissionType: json['commissionType'] ?? 'Referral Commission',
    commissionAmount: (json['commissionAmount'] ?? 0).toDouble(),
    transactionDate: json['transactionDate'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'commissionType': commissionType,
    'commissionAmount': commissionAmount,
    'transactionDate': transactionDate,
  };
}

class PerformanceLevelMaster {
  final String id;
  final String levelName; // 'Bronze' | 'Silver' | 'Gold' | 'Platinum'
  final double minCommission;
  final double commissionPercentage;

  PerformanceLevelMaster({
    required this.id,
    required this.levelName,
    required this.minCommission,
    required this.commissionPercentage,
  });

  factory PerformanceLevelMaster.fromJson(Map<String, dynamic> json) => PerformanceLevelMaster(
    id: json['id'] ?? '',
    levelName: json['levelName'] ?? 'Bronze',
    minCommission: (json['minCommission'] ?? 0).toDouble(),
    commissionPercentage: (json['commissionPercentage'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'levelName': levelName,
    'minCommission': minCommission,
    'commissionPercentage': commissionPercentage,
  };
}

class PartnerPerformance {
  final String id;
  final String partnerId;
  final String partnerName;
  final double totalSales;
  final double totalCommissions;
  final int leadsReferred;
  final int dealsClosed;

  PartnerPerformance({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.totalSales,
    required this.totalCommissions,
    required this.leadsReferred,
    required this.dealsClosed,
  });

  factory PartnerPerformance.fromJson(Map<String, dynamic> json) => PartnerPerformance(
    id: json['id'] ?? '',
    partnerId: json['partnerId'] ?? '',
    partnerName: json['partnerName'] ?? '',
    totalSales: (json['totalSales'] ?? 0).toDouble(),
    totalCommissions: (json['totalCommissions'] ?? 0).toDouble(),
    leadsReferred: (json['leadsReferred'] ?? 0).toInt(),
    dealsClosed: (json['dealsClosed'] ?? 0).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'partnerId': partnerId,
    'partnerName': partnerName,
    'totalSales': totalSales,
    'totalCommissions': totalCommissions,
    'leadsReferred': leadsReferred,
    'dealsClosed': dealsClosed,
  };
}

class SponsorInfo {
  final String id;
  final String name;
  final String status;

  SponsorInfo({
    required this.id,
    required this.name,
    required this.status,
  });

  factory SponsorInfo.fromJson(Map<String, dynamic> json) => SponsorInfo(
    id: (json['id'] ?? json['partnerId'] ?? '').toString(),
    name: (json['name'] ?? json['partnerName'] ?? 'Direct Sponsor').toString(),
    status: (json['status'] ?? 'Active').toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'status': status,
  };
}

class CommissionSummary {
  final double pending;
  final double confirmed;
  final double payable;
  final double paid;

  CommissionSummary({
    required this.pending,
    required this.confirmed,
    required this.payable,
    required this.paid,
  });

  static double _numToDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  factory CommissionSummary.fromJson(Map<String, dynamic> json) {
    final earned = _numToDouble(json['commissionEarned'] ?? json['earned'] ?? json['confirmed']);
    final pay = _numToDouble(json['commissionPayable'] ?? json['payable']);
    final p = _numToDouble(json['commissionPaid'] ?? json['paid']);
    final pend = _numToDouble(json['pending']);
    final conf = _numToDouble(json['confirmed']);

    return CommissionSummary(
      pending: pend,
      confirmed: conf > 0 ? conf : earned,
      payable: pay,
      paid: p,
    );
  }

  Map<String, dynamic> toJson() => {
    'pending': pending,
    'confirmed': confirmed,
    'payable': payable,
    'paid': paid,
  };
}

class CommissionHistoryItem {
  final String id;
  final String orderId;
  final String orderNumber;
  final int level; // 1 to 5
  final double commissionBaseAmount;
  final double commissionRate;
  final double commissionAmount;
  final String status; // 'PENDING' | 'CONFIRMED' | 'PAYABLE' | 'PAID' | 'REVERSED'
  final String createdAt;

  CommissionHistoryItem({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.level,
    required this.commissionBaseAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.status,
    required this.createdAt,
  });

  static double _numToDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  static int _numToInt(dynamic val, [int fallback = 1]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }

  factory CommissionHistoryItem.fromJson(Map<String, dynamic> json) => CommissionHistoryItem(
    id: (json['id'] ?? json['_id'] ?? json['transactionId'] ?? '').toString(),
    orderId: (json['orderId'] ?? '').toString(),
    orderNumber: (json['orderNumber'] ?? json['orderId'] ?? '').toString(),
    level: _numToInt(json['level'] ?? json['referralLevel'], 1),
    commissionBaseAmount: _numToDouble(json['commissionBaseAmount'] ?? json['commissionBase'] ?? json['baseAmount']),
    commissionRate: _numToDouble(json['commissionRate'] ?? json['rate']),
    commissionAmount: _numToDouble(json['commissionAmount'] ?? json['amount']),
    status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
    createdAt: (json['createdAt'] ?? json['date'] ?? json['transactionDate'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderId': orderId,
    'orderNumber': orderNumber,
    'level': level,
    'commissionBaseAmount': commissionBaseAmount,
    'commissionRate': commissionRate,
    'commissionAmount': commissionAmount,
    'status': status,
    'createdAt': createdAt,
  };
}

class ReferralInfo {
  final String referralCode;
  final String referralLink;
  final String partnerStatus;
  final String partnerLevel;
  final int referralCount;
  final int qualifiedCount;
  final SponsorInfo? sponsor;
  final CommissionSummary commissionSummary;

  ReferralInfo({
    required this.referralCode,
    required this.referralLink,
    required this.partnerStatus,
    required this.partnerLevel,
    required this.referralCount,
    required this.qualifiedCount,
    this.sponsor,
    required this.commissionSummary,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map<String, dynamic>? ?? json;
    final sponsorJson = json['sponsor'] as Map<String, dynamic>?;
    final summaryJson = json['commissionSummary'] as Map<String, dynamic>? ?? json['earnings'] as Map<String, dynamic>? ?? json;

    final code = (partner['referralCode'] ?? partner['referralcode'] ?? partner['id'] ?? '').toString();
    final link = (partner['referralLink'] ?? 'https://violeafy.com/ref/$code').toString();

    return ReferralInfo(
      referralCode: code,
      referralLink: link,
      partnerStatus: (partner['status'] ?? partner['partnerStatus'] ?? 'Active').toString(),
      partnerLevel: (partner['level'] ?? partner['partnerLevel'] ?? partner['partnerLevelName'] ?? partner['tier'] ?? 'Bronze').toString(),
      referralCount: (json['referralCount'] ?? json['totalReferrals'] ?? (json['referrals'] is List ? (json['referrals'] as List).length : 0)).toInt(),
      qualifiedCount: (json['qualifiedCount'] ?? 0).toInt(),
      sponsor: sponsorJson != null ? SponsorInfo.fromJson(sponsorJson) : null,
      commissionSummary: CommissionSummary.fromJson(summaryJson),
    );
  }

  Map<String, dynamic> toJson() => {
    'referralCode': referralCode,
    'referralLink': referralLink,
    'partnerStatus': partnerStatus,
    'partnerLevel': partnerLevel,
    'referralCount': referralCount,
    'qualifiedCount': qualifiedCount,
    'sponsor': sponsor?.toJson(),
    'commissionSummary': commissionSummary.toJson(),
  };
}

// --- CATEGORY, BRAND, & BRAND OWNER MODELS ---
class ProductCategory {
  final String id;
  final String name;
  final String? description;
  final String status;
  final String? imageId;
  final String? imageUrl;

  ProductCategory({
    required this.id,
    required this.name,
    this.description,
    this.status = 'Active',
    this.imageId,
    this.imageUrl,
  });

  factory ProductCategory.fromJson(Map<String, dynamic> json) => ProductCategory(
    id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['category_name']?.toString() ?? json['category']?.toString() ?? '',
    description: json['description']?.toString(),
    status: json['status']?.toString() ?? 'Active',
    imageId: json['imageId']?.toString() ?? json['imageRef']?.toString() ?? json['documentId']?.toString(),
    imageUrl: json['imageUrl']?.toString() != null 
        ? EnvConfig.normalizeUrl(json['imageUrl'].toString()) 
        : (json['image']?.toString() != null ? EnvConfig.normalizeUrl(json['image'].toString()) : null),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'status': status,
    'imageId': imageId,
    'imageUrl': imageUrl,
  };
}

class ProductBrand {
  final String id;
  final String name;
  final String? brandOwnerId;
  final String? description;
  final String status;
  final String? imageId;
  final String? imageUrl;

  ProductBrand({
    required this.id,
    required this.name,
    this.brandOwnerId,
    this.description,
    this.status = 'Active',
    this.imageId,
    this.imageUrl,
  });

  factory ProductBrand.fromJson(Map<String, dynamic> json) => ProductBrand(
    id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['brand_name']?.toString() ?? json['brand']?.toString() ?? '',
    brandOwnerId: json['brandOwnerId']?.toString() ?? json['brand_owner_id']?.toString(),
    description: json['description']?.toString(),
    status: json['status']?.toString() ?? 'Active',
    imageId: json['imageId']?.toString() ?? json['imageRef']?.toString() ?? json['documentId']?.toString(),
    imageUrl: json['imageUrl']?.toString() != null 
        ? EnvConfig.normalizeUrl(json['imageUrl'].toString()) 
        : (json['image']?.toString() != null ? EnvConfig.normalizeUrl(json['image'].toString()) : null),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brandOwnerId': brandOwnerId,
    'description': description,
    'status': status,
    'imageId': imageId,
    'imageUrl': imageUrl,
  };
}

class ProductBrandOwner {
  final String id;
  final String name;
  final String? company;
  final String status;
  final String? imageId;
  final String? imageUrl;

  ProductBrandOwner({
    required this.id,
    required this.name,
    this.company,
    this.status = 'Active',
    this.imageId,
    this.imageUrl,
  });

  factory ProductBrandOwner.fromJson(Map<String, dynamic> json) => ProductBrandOwner(
    id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['owner_name']?.toString() ?? json['brandOwner']?.toString() ?? '',
    company: json['company']?.toString(),
    status: json['status']?.toString() ?? 'Active',
    imageId: json['imageId']?.toString() ?? json['imageRef']?.toString() ?? json['documentId']?.toString(),
    imageUrl: json['imageUrl']?.toString() != null 
        ? EnvConfig.normalizeUrl(json['imageUrl'].toString()) 
        : (json['image']?.toString() != null ? EnvConfig.normalizeUrl(json['image'].toString()) : null),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'status': status,
    'imageId': imageId,
    'imageUrl': imageUrl,
  };
}


