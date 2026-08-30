import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../core/config/env_config.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';

class ShoppingRepository {
  final ApiClient _apiClient = ApiClient();
  final FirebaseFirestore? firestore;
  String? lastLeadSaveError;

  ShoppingRepository({this.firestore});

  static List<Lead> filterLeadsForCurrentUser(List<Lead> leads, CustomerPerformance? currentUser) {
    if (currentUser == null) return const [];

    final userReferralCodes = <String>{
      currentUser.referralCode ?? '',
      currentUser.id,
      currentUser.mobileNumber,
      currentUser.mobilenumberwithcountrycode,
      currentUser.name,
    }.where((value) => value.trim().isNotEmpty).toSet();

    if (userReferralCodes.isEmpty) return leads;

    return leads.where((lead) {
      final leadReferralCode = (lead.referralCode ?? '').trim();
      final leadReferralPartner = (lead.referralPartner ?? '').trim();
      final leadReferralMobile = (lead.referralmobileno ?? '').trim();
      final customerPhone = (currentUser.mobileNumber).trim();
      final customerMobileWithCode = (currentUser.mobilenumberwithcountrycode).trim();

      final matchesReferralCode = leadReferralCode.isNotEmpty && userReferralCodes.contains(leadReferralCode);
      final matchesCustomerId = leadReferralCode.isNotEmpty && leadReferralCode == currentUser.id;
      final matchesPartnerName = leadReferralPartner.isNotEmpty && leadReferralPartner == currentUser.name;
      final matchesPartnerPhone = leadReferralMobile.isNotEmpty &&
          (leadReferralMobile == customerPhone || leadReferralMobile == customerMobileWithCode);

      return matchesReferralCode || matchesCustomerId || matchesPartnerName || matchesPartnerPhone;
    }).toList();
  }

  // Local sync cache for Cart & Wishlist
  final List<SalesProduct> _cartItems = [];
  final List<String> _wishlistProductIds = [];

  // Fetch products from Authoritative Server API with Firestore probe fallback
  Future<List<ProductPerformance>> getProducts() async {
    try {
      debugPrint('[ShoppingRepository] Fetching products from Server API...');
      final response = await _apiClient.get('/api/products');
      if (response != null && response is List && response.isNotEmpty) {
        final list = <ProductPerformance>[];
        for (final item in response) {
          try {
            if (item is Map<String, dynamic>) {
              list.add(ProductPerformance.fromJson(item));
            } else if (item is Map) {
              list.add(ProductPerformance.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (itemErr) {
            debugPrint('[ShoppingRepository] Error parsing API product item: $itemErr');
          }
        }
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Server API fetch error for products: $e');
    }

    // Fallback to Firestore probe
    try {
      if (firestore != null) {
        debugPrint('[ShoppingRepository] Falling back to Firestore probe for products...');
        final snapshot = await firestore!
            .collection('products')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          final list = <ProductPerformance>[];
          for (final doc in snapshot.docs) {
            try {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              list.add(ProductPerformance.fromJson(data));
            } catch (docErr) {
              debugPrint('[ShoppingRepository] Error parsing Firestore doc ${doc.id}: $docErr');
            }
          }
          if (list.isNotEmpty) return list;
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Firestore fallback error fetching products: $e');
    }
    return [];
  }

  // Fetch product by ID
  Future<ProductPerformance?> getProductById(String id) async {
    try {
      if (firestore != null) {
        final doc = await firestore!
            .collection('products')
            .doc(id)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists) {
          final data = doc.data()!;
          data['id'] = doc.id;
          return ProductPerformance.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Firestore fetch error for ID $id: $e');
    }

    final products = await getProducts();
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // Authoritative Category Data Retrieval from Server-Side API
  Future<List<ProductCategory>> getCategoryModels() async {
    try {
      final response = await _apiClient.get('/api/categories');
      if (response != null && response is List && response.isNotEmpty) {
        final list = response.map((item) {
          if (item is Map<String, dynamic>) {
            return ProductCategory.fromJson(item);
          } else if (item is Map) {
            return ProductCategory.fromJson(Map<String, dynamic>.from(item));
          } else {
            return ProductCategory(id: item.toString(), name: item.toString());
          }
        }).where((cat) => cat.name.trim().isNotEmpty).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching categories from API: $e');
    }

    // Fallback 1: Firestore collections ('product_categories' or 'categories')
    try {
      if (firestore != null) {
        final snapshot = await firestore!
            .collection('product_categories')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) => ProductCategory.fromJson({...doc.data(), 'id': doc.id})).toList();
        }

        final legacySnapshot = await firestore!
            .collection('categories')
            .get()
            .timeout(const Duration(seconds: 5));
        if (legacySnapshot.docs.isNotEmpty) {
          return legacySnapshot.docs.map((doc) => ProductCategory(id: doc.id, name: doc.id)).toList();
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching categories from Firestore fallback: $e');
    }

    // Fallback 2: Derive categories from products database catalog
    try {
      final products = await getProducts();
      final categorySet = <String>{};
      for (final p in products) {
        if (p.category != null && p.category!.trim().isNotEmpty) {
          categorySet.add(p.category!.trim());
        }
      }
      if (categorySet.isNotEmpty) {
        return categorySet.map((cat) => ProductCategory(id: cat, name: cat, description: '$cat products')).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error deriving categories from products fallback: $e');
    }

    // Fallback 3: Standard default master categories
    return [
      ProductCategory(id: 'cat_fruits', name: 'Fruits', description: 'Fresh Farm Fruits'),
      ProductCategory(id: 'cat_vegetables', name: 'Vegetables', description: 'Organic Vegetables'),
      ProductCategory(id: 'cat_dairy', name: 'Dairy', description: 'Farm Fresh Milk & Dairy'),
      ProductCategory(id: 'cat_grains', name: 'Grains', description: 'Quality Grains & Rice'),
      ProductCategory(id: 'cat_beverages', name: 'Beverages', description: 'Refreshing Drinks'),
      ProductCategory(id: 'cat_snacks', name: 'Snacks', description: 'Tasty Treats & Sweets'),
    ];
  }

  // Legacy/Helper String list for categories UI
  Future<List<String>> getCategories() async {
    final models = await getCategoryModels();
    if (models.isNotEmpty) {
      return models.map((m) => m.name).where((name) => name.isNotEmpty).toList();
    }
    return ['All', 'Fruits', 'Vegetables', 'Dairy', 'Grains', 'Beverages', 'Snacks'];
  }

  // Authoritative Brand Data Retrieval from Server-Side API
  Future<List<ProductBrand>> getBrandModels() async {
    try {
      final response = await _apiClient.get('/api/brands');
      if (response != null && response is List && response.isNotEmpty) {
        final list = response.map((item) {
          if (item is Map<String, dynamic>) {
            return ProductBrand.fromJson(item);
          } else if (item is Map) {
            return ProductBrand.fromJson(Map<String, dynamic>.from(item));
          } else {
            return ProductBrand(id: item.toString(), name: item.toString());
          }
        }).where((b) => b.name.trim().isNotEmpty).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching brands from API: $e');
    }

    try {
      if (firestore != null) {
        final snapshot = await firestore!
            .collection('product_brands')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) => ProductBrand.fromJson({...doc.data(), 'id': doc.id})).toList();
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching brands from Firestore fallback: $e');
    }

    try {
      final products = await getProducts();
      final brandSet = <String>{};
      for (final p in products) {
        if (p.brand != null && p.brand!.trim().isNotEmpty) {
          brandSet.add(p.brand!.trim());
        }
      }
      if (brandSet.isNotEmpty) {
        return brandSet.map((b) => ProductBrand(id: b, name: b)).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error deriving brands from products fallback: $e');
    }

    return [
      ProductBrand(id: 'brand_leafy', name: 'Leafy Organic'),
      ProductBrand(id: 'brand_vamjo', name: 'Vamjo Farm'),
    ];
  }

  // Authoritative Brand Owner Data Retrieval from Server-Side API
  Future<List<ProductBrandOwner>> getBrandOwnerModels() async {
    try {
      final response = await _apiClient.get('/api/brand-owners');
      if (response != null && response is List && response.isNotEmpty) {
        final list = response.map((item) {
          if (item is Map<String, dynamic>) {
            return ProductBrandOwner.fromJson(item);
          } else if (item is Map) {
            return ProductBrandOwner.fromJson(Map<String, dynamic>.from(item));
          } else {
            return ProductBrandOwner(id: item.toString(), name: item.toString());
          }
        }).where((o) => o.name.trim().isNotEmpty).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching brand owners from API: $e');
    }

    try {
      if (firestore != null) {
        final snapshot = await firestore!
            .collection('product_brand_owners')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) => ProductBrandOwner.fromJson({...doc.data(), 'id': doc.id})).toList();
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching brand owners from Firestore fallback: $e');
    }

    try {
      final products = await getProducts();
      final ownerSet = <String>{};
      for (final p in products) {
        if (p.brandOwner != null && p.brandOwner!.trim().isNotEmpty) {
          ownerSet.add(p.brandOwner!.trim());
        }
      }
      if (ownerSet.isNotEmpty) {
        return ownerSet.map((o) => ProductBrandOwner(id: o, name: o, company: o)).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error deriving brand owners from products fallback: $e');
    }

    return [
      ProductBrandOwner(id: 'owner_violeafy', name: 'Violeafy Group', company: 'Violeafy Pvt Ltd'),
    ];
  }

  // Picture / Image Retrieval from Firebase Firestore
  Future<String?> getFirestoreImageUrl(String collection, String docIdOrRef) async {
    if (firestore == null || docIdOrRef.trim().isEmpty) return null;
    try {
      final doc = await firestore!
          .collection(collection)
          .doc(docIdOrRef.trim())
          .get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final url = data['imageUrl'] ?? data['image'] ?? data['picture'] ?? data['photoUrl'] ?? data['url'];
        if (url != null) return EnvConfig.normalizeUrl(url.toString());
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching image from Firestore collection ($collection/$docIdOrRef): $e');
    }
    return null;
  }


  // Fetch dynamic home banners from Server API with Firestore fallback
  Future<List<Map<String, String>>> getBanners() async {
    try {
      final response = await _apiClient.get('/api/banners');
      if (response != null && response is List && response.isNotEmpty) {
        return response.map((item) {
          final Map<String, dynamic> map = item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map);
          return {
            'title': (map['name'] ?? map['title'] ?? 'Leafy Special Offer').toString(),
            'subtitle': (map['description'] ?? map['subtitle'] ?? 'Fresh Farm Discounts').toString(),
            'image': EnvConfig.normalizeUrl((map['imageUrl'] ?? map['image'] ?? '').toString()),
            'code': (map['code'] ?? map['couponCode'] ?? 'LEAFY10').toString(),
          };
        }).toList();
      }

      final fallbackResponse = await _apiClient.get('/api/data/campaigns');
      if (fallbackResponse != null && fallbackResponse is List && fallbackResponse.isNotEmpty) {
        return fallbackResponse.map((item) {
          final Map<String, dynamic> map = item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map);
          return {
            'title': (map['name'] ?? map['title'] ?? 'Leafy Special Offer').toString(),
            'subtitle': (map['description'] ?? map['subtitle'] ?? 'Fresh Farm Discounts').toString(),
            'image': EnvConfig.normalizeUrl((map['imageUrl'] ?? map['image'] ?? 'https://images.unsplash.com/photo-1553279768-865429fa0078?q=80&w=800&auto=format&fit=crop').toString()),
            'code': (map['code'] ?? map['couponCode'] ?? 'LEAFY10').toString(),
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching banners from API: $e');
    }

    try {
      if (firestore != null) {
        final snapshot = await firestore!
            .collection('campaigns')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final map = doc.data();
            return {
              'title': (map['name'] ?? map['title'] ?? 'Leafy Special Offer').toString(),
              'subtitle': (map['description'] ?? map['subtitle'] ?? 'Fresh Farm Discounts').toString(),
              'image': EnvConfig.normalizeUrl((map['imageUrl'] ?? map['image'] ?? '').toString()),
              'code': (map['code'] ?? map['couponCode'] ?? '').toString(),
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Firestore fallback error fetching banners: $e');
    }
    return [];
  }

  // Fetch active, currently redeemable coupons via Server API
  Future<List<Coupon>> getCoupons() async {
    try {
      final response = await _apiClient.get('/api/data/coupons');
      if (response != null && response is List && response.isNotEmpty) {
        return response.map((item) => Coupon.fromJson(item)).where((coupon) => coupon.isActive).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching coupons from API: $e');
    }

    try {
      if (firestore != null) {
        final snapshot = await firestore!
            .collection('coupons')
            .get()
            .timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return Coupon.fromJson(data);
          }).where((coupon) => coupon.isActive).toList();
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Firestore fallback error fetching coupons: $e');
    }
    return [];
  }

  // Cart Management
  List<SalesProduct> getCartItems() => List.unmodifiable(_cartItems);

  void addToCart(ProductPerformance product, {int quantity = 1}) {
    final index = _cartItems.indexWhere((item) => item.productId == product.id);
    if (index >= 0) {
      final existing = _cartItems[index];
      _cartItems[index] = SalesProduct(
        productId: existing.productId,
        productName: existing.productName,
        imageUrl: existing.imageUrl,
        quantity: existing.quantity + quantity,
        price: existing.price,
        gstPercentage: existing.gstPercentage,
        hsnCode: existing.hsnCode,
        category: existing.category,
        brand: existing.brand,
      );
    } else {
      _cartItems.add(SalesProduct(
        productId: product.id,
        productName: product.name,
        imageUrl: product.imageUrl ?? (product.images != null && product.images!.isNotEmpty ? product.images!.first : null),
        quantity: quantity,
        price: product.offerPrice ?? product.onlinePrice,
        gstPercentage: product.gstPercentage,
        hsnCode: product.hsnCode,
        category: product.category,
        brand: product.brand,
      ));
    }
    _syncCartToBackend();
  }

  void addInvoiceItemsToCart(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final productId = item['productId']?.toString() ?? '';
      if (productId.isEmpty) continue;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final index = _cartItems.indexWhere((cartItem) => cartItem.productId == productId);
      final product = SalesProduct(
        productId: productId,
        productName: item['itemDetails']?.toString() ?? '',
        imageUrl: item['imageUrl']?.toString(),
        quantity: quantity,
        price: (item['rate'] as num?)?.toDouble() ?? 0,
        gstPercentage: (item['gstRate'] as num?)?.toDouble(),
        hsnCode: item['hsnCode']?.toString(),
      );
      if (index >= 0) {
        final existing = _cartItems[index];
        _cartItems[index] = SalesProduct(
          productId: existing.productId,
          productName: existing.productName,
          imageUrl: existing.imageUrl,
          quantity: existing.quantity + quantity,
          price: existing.price,
          gstPercentage: existing.gstPercentage,
          hsnCode: existing.hsnCode ?? product.hsnCode,
        );
      } else {
        _cartItems.add(product);
      }
    }
    _syncCartToBackend();
  }

  void removeFromCart(String productId) {
    _cartItems.removeWhere((item) => item.productId == productId);
    _syncCartToBackend();
  }

  void updateQuantity(String productId, int newQuantity) {
    if (newQuantity <= 0) {
      removeFromCart(productId);
      return;
    }
    final index = _cartItems.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      final item = _cartItems[index];
      _cartItems[index] = SalesProduct(
        productId: item.productId,
        productName: item.productName,
        imageUrl: item.imageUrl,
        quantity: newQuantity,
        price: item.price,
        gstPercentage: item.gstPercentage,
        hsnCode: item.hsnCode,
        category: item.category,
        brand: item.brand,
      );
    }
    _syncCartToBackend();
  }

  void clearCart() {
    _cartItems.clear();
    _syncCartToBackend();
  }

  double getCartTotal() {
    return _cartItems.fold(0, (total, item) => total + (item.price * item.quantity));
  }

  Future<void> _syncCartToBackend() async {
    try {
      await _apiClient.post('/api/data/shopping_carts', {
        'id': 'user_active_cart',
        'items': _cartItems.map((item) => item.toJson()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ShoppingRepository] Cart sync error: $e');
    }
  }

  // Wishlist Management
  List<String> getWishlistIds() => List.unmodifiable(_wishlistProductIds);

  bool isWishlisted(String productId) => _wishlistProductIds.contains(productId);

  void toggleWishlist(String productId) {
    if (_wishlistProductIds.contains(productId)) {
      _wishlistProductIds.remove(productId);
    } else {
      _wishlistProductIds.add(productId);
    }
    _syncWishlistToBackend();
  }

  Future<void> _syncWishlistToBackend() async {
    try {
      await _apiClient.post('/api/data/wishlists', {
        'id': 'user_active_wishlist',
        'productIds': _wishlistProductIds,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[ShoppingRepository] Wishlist sync error: $e');
    }
  }

  // Fetch Sales Orders from backend
  Future<List<SalesOrder>> getSalesOrders() async {
    try {
      final response = await _apiClient.get('/api/sales-orders');
      if (response != null && response is List) {
        return response.map((item) => SalesOrder.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching sales orders: $e');
    }
    return [];
  }

  // Request authoritative server-side GST calculation
  Future<Map<String, dynamic>?> calculateServerGst(List<SalesProduct> items) async {
    try {
      final response = await _apiClient.post('/api/orders/calculate-gst', {
        'items': items.map((item) => item.toJson()).toList(),
      });
      if (response != null && response is Map && response['calculation'] is Map) {
        return Map<String, dynamic>.from(response['calculation'] as Map);
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Server GST calculation error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> getInvoice(String invoiceOrOrderId) async {
    final response = await _apiClient.get('/api/invoices/${Uri.encodeComponent(invoiceOrOrderId)}');
    if (response is! Map || response['invoice'] is! Map) {
      throw Exception('Invalid invoice response');
    }
    return Map<String, dynamic>.from(response['invoice'] as Map);
  }

  // Fetch payment status from Server API
  Future<Map<String, dynamic>?> getPaymentStatus(String transactionId) async {
    try {
      final response = await _apiClient.get('/api/payment/status/${Uri.encodeComponent(transactionId)}');
      if (response != null && response is Map<String, dynamic>) {
        return response;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching payment status for $transactionId: $e');
    }
    return null;
  }

  Future<List<Lead>> getLeads() async {
    List<Lead> leads = [];
    try {
      if (firestore != null) {
        final snapshot = await firestore!.collection('leads').get().timeout(const Duration(seconds: 5));
        if (snapshot.docs.isNotEmpty) {
          leads = snapshot.docs.map((doc) => Lead.fromJson({...doc.data(), 'id': doc.id})).toList();
        }
      }
      if (leads.isEmpty) {
        final response = await _apiClient.get('/api/data/leads');
        if (response is List) leads = response.map((item) => Lead.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching leads: $e');
    }

    final currentUser = await getCurrentCustomer();
    return filterLeadsForCurrentUser(leads, currentUser);
  }

  Future<bool> saveLead(Lead lead) async {
    lastLeadSaveError = null;
    try {
      final payload = lead.toJson();
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        CustomerPerformance? customer;
        if (firestore != null) {
          try {
            final queryByAuth = await firestore!
                .collection('customers')
                .where('authUid', isEqualTo: user.uid)
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 5));
            if (queryByAuth.docs.isNotEmpty) {
              final doc = queryByAuth.docs.first;
              customer = CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
            } else {
              final userPhone = user.phoneNumber ?? '';
              final cleanUserPhone = userPhone.replaceAll(RegExp(r'\D'), '');
              if (cleanUserPhone.isNotEmpty) {
                final targetMobile = cleanUserPhone.length > 10 ? cleanUserPhone.substring(cleanUserPhone.length - 10) : cleanUserPhone;
                final queryByMobile = await firestore!
                    .collection('customers')
                    .where('mobileNumber', isEqualTo: targetMobile)
                    .limit(1)
                    .get()
                    .timeout(const Duration(seconds: 5));
                if (queryByMobile.docs.isNotEmpty) {
                  final doc = queryByMobile.docs.first;
                  customer = CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
                }
              }
            }
          } catch (e) {
            debugPrint('[ShoppingRepository] Error looking up customer profile for lead referral: $e');
          }
        }

        final customerId = customer?.id.isNotEmpty == true ? customer!.id : user.uid;
        final partnerName = customer?.name.isNotEmpty == true ? customer!.name : (user.displayName ?? 'Referral User');
        final referralMobileWithCode = customer?.mobilenumberwithcountrycode.isNotEmpty == true
            ? customer!.mobilenumberwithcountrycode
            : (user.phoneNumber ?? '');

        payload['referralCode'] = customerId;
        payload['referralcode'] = customerId;
        payload['referralPartner'] = partnerName;
        payload['referralpartner'] = partnerName;
        payload['referralmobileno'] = referralMobileWithCode;
      }
      if (firestore != null) {
        final phone = lead.phone.replaceAll(RegExp(r'\D'), '');
        if (phone.isEmpty) {
          lastLeadSaveError = 'A valid WhatsApp mobile number is required.';
          return false;
        }
        payload['phone'] = phone;
        final countryCode = lead.countrymobilecode.isNotEmpty ? lead.countrymobilecode : '+91';
        payload['countrymobilecode'] = countryCode;
        payload['mobilenumberwithcountrycode'] = phone.startsWith('+') ? phone : '$countryCode$phone';
        final reservationRef = firestore!.collection('lead_mobile_index').doc(phone);
        final leadRef = firestore!.collection('leads').doc(lead.id);
        final existingLeads = await firestore!
            .collection('leads')
            .where('phone', isEqualTo: phone)
            .limit(2)
            .get()
            .timeout(const Duration(seconds: 5));
        if (existingLeads.docs.any((doc) => doc.id != lead.id)) {
          lastLeadSaveError = 'Mobile number is already reserved. Duplicate number is not allowed.';
          return false;
        }
        final existingLead = await leadRef.get().timeout(const Duration(seconds: 5));
        if (existingLead.exists) {
          await leadRef.set(payload, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
          await reservationRef.set({'leadId': lead.id, 'phone': phone}, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
          return true;
        }
        final reservation = await reservationRef.get().timeout(const Duration(seconds: 5));
        if (reservation.exists && reservation.data()?['leadId'] != lead.id) {
          lastLeadSaveError = 'Mobile number is already reserved. Duplicate number is not allowed.';
          return false;
        }
        final batch = firestore!.batch();
        batch.set(reservationRef, {'leadId': lead.id, 'phone': phone}, SetOptions(merge: true));
        batch.set(leadRef, payload, SetOptions(merge: true));
        await batch.commit().timeout(const Duration(seconds: 10));
      } else {
        await _apiClient.post('/api/data/leads', payload);
      }
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error saving lead: $e');
      final errorCode = e is FirebaseException ? e.code : null;
      final errorMessage = e is FirebaseException ? e.message : e.toString();
      lastLeadSaveError = errorCode == 'permission-denied'
          ? 'You do not have permission to save this referral.'
          : 'Unable to save lead${errorCode == null ? '' : ' ($errorCode)'}: ${errorMessage ?? 'Unknown error'}';
      return false;
    }
  }

  Future<bool> deleteLead(String id) async {
    try {
      if (firestore != null) {
        await firestore!.collection('leads').doc(id).delete().timeout(const Duration(seconds: 5));
      } else {
        await _apiClient.delete('/api/data/leads/$id');
      }
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error deleting lead: $e');
      return false;
    }
  }

  Future<bool> saveCustomer(CustomerPerformance customer) async {
    try {
      return await resolveOrCreateCustomer(customer.mobileNumber, draft: customer) != null;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error saving converted customer: $e');
      lastLeadSaveError = 'Unable to convert referral: $e';
      return false;
    }
  }

  Future<CustomerPerformance?> resolveOrCreateCustomer(String mobile, {CustomerPerformance? draft}) async {
    final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');
    if (normalizedMobile.isEmpty) return null;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;

    try {
      if (firestore != null) {
        if (user != null) {
          final linked = await firestore!
              .collection('customers')
              .where('authUid', isEqualTo: user.uid)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 5));
          if (linked.docs.isNotEmpty) {
            final doc = linked.docs.first;
            return CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
          }
        }

        final existing = await _findCustomerByMobile(normalizedMobile);
        if (existing != null) return existing;
        final lead = await _findLeadByMobile(normalizedMobile);
        final payload = draft?.toJson() ?? <String, dynamic>{};
        final countryCode = draft?.countrymobilecode.isNotEmpty == true ? draft!.countrymobilecode : '+91';
        payload['mobileNumber'] = normalizedMobile;
        payload['countrymobilecode'] = countryCode;
        payload['mobilenumberwithcountrycode'] = normalizedMobile.startsWith('+') ? normalizedMobile : '$countryCode$normalizedMobile';
        payload['authUid'] = user?.uid;
        payload['leadslinkid'] = lead?.id;
        payload['referralcode'] = lead?.referralCode;
        payload['referralpartner'] = lead?.referralPartner;
        payload['leadId'] = lead?.id;
        payload['referralCode'] = lead?.referralCode;

        final indexRef = firestore!.collection('customer_mobile_index').doc(normalizedMobile);
        return firestore!.runTransaction<CustomerPerformance?>((transaction) async {
          final index = await transaction.get(indexRef);
          if (index.exists) {
            final customerId = index.data()?['customerId'];
            if (customerId is String && customerId.isNotEmpty) {
              final existingDoc = await transaction.get(firestore!.collection('customers').doc(customerId));
              if (existingDoc.exists) {
                return CustomerPerformance.fromJson({...existingDoc.data()!, 'id': existingDoc.id});
              }
            }
          }
          final customerRef = firestore!.collection('customers').doc();
          payload['id'] = customerRef.id;
          transaction.set(customerRef, payload);
          transaction.set(indexRef, {'customerId': customerRef.id, 'mobileNumber': normalizedMobile});
          return CustomerPerformance.fromJson(payload);
        }).timeout(const Duration(seconds: 10));
      }

      final response = await _apiClient.post('/api/data/customers', {
        ...(draft?.toJson() ?? <String, dynamic>{}),
        'mobileNumber': normalizedMobile,
      });
      if (response is Map<String, dynamic>) {
        final item = response['item'];
        if (item is Map<String, dynamic>) return CustomerPerformance.fromJson(item);
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error resolving customer: $e');
      lastLeadSaveError = 'Unable to convert referral: $e';
    }
    return null;
  }

  Future<CustomerPerformance?> getCurrentCustomer() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      if (firestore != null) {
        final linked = await firestore!
            .collection('customers')
            .where('authUid', isEqualTo: user.uid)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));
        if (linked.docs.isNotEmpty) {
          final doc = linked.docs.first;
          return CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
        }
        if (user.email != null && user.email!.isNotEmpty) {
          final emailMatch = await firestore!
              .collection('customers')
              .where('email', isEqualTo: user.email)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 5));
          if (emailMatch.docs.isNotEmpty) {
            final doc = emailMatch.docs.first;
            return CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
          }
        }
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
          final phoneMatch = await firestore!
              .collection('customers')
              .where('mobileNumber', isEqualTo: user.phoneNumber)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 5));
          if (phoneMatch.docs.isNotEmpty) {
            final doc = phoneMatch.docs.first;
            return CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
          }
        }
        return null;
      }

      final response = await _apiClient.get('/api/data/customers');
      if (response is List) {
        for (final item in response) {
          if (item is Map<String, dynamic> && item['authUid'] == user.uid) {
            return CustomerPerformance.fromJson(item);
          }
        }
        for (final item in response) {
          if (item is Map<String, dynamic> &&
              ((user.email != null && item['email'] == user.email) ||
                  (user.phoneNumber != null && item['mobileNumber'] == user.phoneNumber))) {
            return CustomerPerformance.fromJson(item);
          }
        }
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching current customer: $e');
    }
    return null;
  }

  Future<CustomerPerformance?> _findCustomerByMobile(String mobile) async {
    final mobileSnapshot = await firestore!
        .collection('customers')
        .where('mobileNumber', isEqualTo: mobile)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
    if (mobileSnapshot.docs.isNotEmpty) {
      final doc = mobileSnapshot.docs.first;
      return CustomerPerformance.fromJson({...doc.data(), 'id': doc.id});
    }
    return null;
  }

  Future<Lead?> _findLeadByMobile(String mobile) async {
    final snapshot = await firestore!
        .collection('leads')
        .where('phone', isEqualTo: mobile)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return Lead.fromJson({...doc.data(), 'id': doc.id});
  }

  Future<bool> saveWhatsAppMessage({required String phone, required String text, required String leadId}) async {
    try {
      final message = {
        'id': 'lead_message_${DateTime.now().millisecondsSinceEpoch}',
        'phone': phone,
        'message': text,
        'leadId': leadId,
        'direction': 'Outgoing',
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
      };
      if (firestore != null) {
        await firestore!.collection('whatsapp_messages').doc(message['id'] as String).set(message).timeout(const Duration(seconds: 5));
      } else {
        await _apiClient.post('/api/data/whatsapp_messages', message);
      }
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error saving WhatsApp message: $e');
      return false;
    }
  }

  // Post new order to backend
  Future<bool> createOrder(SalesOrder order) async {
    try {
      await _apiClient.post('/api/data/sales_orders', order.toJson());
      clearCart();
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error creating sales order: $e');
      return false;
    }
  }

  Future<List<CustomerDeliveryAddress>> getCustomerAddresses(String userId) async {
    try {
      final Set<String> candidateKeys = {userId.trim()};
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (user.uid.isNotEmpty) candidateKeys.add(user.uid.trim());
        if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty) {
          final phone = user.phoneNumber!.trim();
          candidateKeys.add(phone);
          final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
          if (cleanDigits.isNotEmpty) candidateKeys.add(cleanDigits);
          if (cleanDigits.length > 10) candidateKeys.add(cleanDigits.substring(cleanDigits.length - 10));
        }
        if (user.email != null && user.email!.trim().isNotEmpty) {
          candidateKeys.add(user.email!.trim());
        }
      }
      candidateKeys.removeWhere((k) => k.isEmpty);

      if (firestore != null) {
        debugPrint('[ShoppingRepository] Fetching delivery addresses from Firestore for candidate keys: $candidateKeys');
        final Map<String, CustomerDeliveryAddress> addressMap = {};

        for (final key in candidateKeys) {
          final byUserId = await firestore!
              .collection('customer_delivery_addresses')
              .where('userId', isEqualTo: key)
              .get()
              .timeout(const Duration(seconds: 5));
          for (final doc in byUserId.docs) {
            addressMap[doc.id] = CustomerDeliveryAddress.fromJson({...doc.data(), 'id': doc.id});
          }

          final byCustomerId = await firestore!
              .collection('customer_delivery_addresses')
              .where('customerId', isEqualTo: key)
              .get()
              .timeout(const Duration(seconds: 5));
          for (final doc in byCustomerId.docs) {
            addressMap[doc.id] = CustomerDeliveryAddress.fromJson({...doc.data(), 'id': doc.id});
          }

          final byMobile = await firestore!
              .collection('customer_delivery_addresses')
              .where('mobileNumber', isEqualTo: key)
              .get()
              .timeout(const Duration(seconds: 5));
          for (final doc in byMobile.docs) {
            addressMap[doc.id] = CustomerDeliveryAddress.fromJson({...doc.data(), 'id': doc.id});
          }
        }

        if (addressMap.isNotEmpty) {
          final result = addressMap.values.toList();
          result.sort((a, b) => (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0));
          return result;
        }
      }

      debugPrint('[ShoppingRepository] Falling back to API for delivery addresses...');
      final response = await _apiClient.get('/api/data/customer_delivery_addresses');
      if (response is List) {
        final List<CustomerDeliveryAddress> matched = [];
        final Set<String> seenIds = {};
        for (final item in response) {
          if (item is Map<String, dynamic>) {
            final addr = CustomerDeliveryAddress.fromJson(item);
            if (candidateKeys.contains(addr.userId) ||
                candidateKeys.contains(addr.customerId) ||
                candidateKeys.contains(addr.mobileNumber)) {
              if (seenIds.add(addr.id)) {
                matched.add(addr);
              }
            }
          }
        }
        matched.sort((a, b) => (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0));
        return matched;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching customer delivery addresses: $e');
    }
    return [];
  }

  Future<CustomerDeliveryAddress?> saveCustomerAddress(CustomerDeliveryAddress address) async {
    try {
      debugPrint('[ShoppingRepository] Saving delivery address: ${address.toJson()}');

      if (firestore != null) {
        await firestore!
            .collection('customer_delivery_addresses')
            .doc(address.id)
            .set(address.toJson())
            .timeout(const Duration(seconds: 5));
        debugPrint('[ShoppingRepository] Delivery address saved to Firestore.');
      } else {
        await _apiClient.post('/api/data/customer_delivery_addresses', address.toJson());
      }

      // Check customer table email sync
      final trimmedEmail = address.email.trim();
      final isEmailValid = trimmedEmail.contains('@') && trimmedEmail.contains('.');
      if (isEmailValid) {
        try {
          final customer = await getCurrentCustomer();
          if (customer != null && customer.email.trim().isEmpty) {
            debugPrint('[ShoppingRepository] Customer email is empty. Updating customer record ${customer.id} with email $trimmedEmail');
            if (firestore != null) {
              await firestore!
                  .collection('customers')
                  .doc(customer.id)
                  .update({'email': trimmedEmail})
                  .timeout(const Duration(seconds: 5));
            } else {
              await _apiClient.post('/api/data/customers/${customer.id}', {'email': trimmedEmail});
            }
          }
        } catch (err) {
          debugPrint('[ShoppingRepository] Error syncing customer email: $err');
        }
      }

      return address;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error saving customer delivery address: $e');
      return null;
    }
  }

  Future<bool> deleteCustomerAddress(String addressId) async {
    try {
      debugPrint('[ShoppingRepository] Deleting delivery address: $addressId');
      if (firestore != null) {
        await firestore!
            .collection('customer_delivery_addresses')
            .doc(addressId)
            .delete()
            .timeout(const Duration(seconds: 5));
        return true;
      }
      await _apiClient.delete('/api/data/customer_delivery_addresses/$addressId');
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error deleting delivery address: $e');
      return false;
    }
  }

  Future<bool> setDefaultCustomerAddress(String addressId, String userId) async {
    try {
      debugPrint('[ShoppingRepository] Setting default delivery address $addressId for user $userId');
      final addresses = await getCustomerAddresses(userId);
      for (final addr in addresses) {
        final shouldBeDefault = addr.id == addressId;
        if (addr.isDefault != shouldBeDefault) {
          final updated = CustomerDeliveryAddress(
            id: addr.id,
            userId: addr.userId,
            customerId: addr.customerId,
            name: addr.name,
            mobileNumber: addr.mobileNumber,
            email: addr.email,
            addressLine: addr.addressLine,
            city: addr.city,
            district: addr.district,
            state: addr.state,
            pincode: addr.pincode,
            isDefault: shouldBeDefault,
          );
          await saveCustomerAddress(updated);
        }
      }
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error setting default delivery address: $e');
      return false;
    }
  }

  // Fetch Pincode-specific Delivery Charge from Authoritative Server API
  Future<DeliveryChargeResult> getDeliveryCharge(String pincode) async {
    final cleanCode = pincode.trim();
    if (cleanCode.isEmpty) {
      return const DeliveryChargeResult(
        success: true,
        pincode: '',
        ruleFound: false,
        deliveryCharge: 0.0,
      );
    }

    try {
      debugPrint('[ShoppingRepository] Looking up delivery charge for pincode: $cleanCode');
      final response = await _apiClient.get('/api/delivery-charges/$cleanCode');
      if (response is Map<String, dynamic>) {
        return DeliveryChargeResult.fromJson(response);
      } else if (response is Map) {
        return DeliveryChargeResult.fromJson(Map<String, dynamic>.from(response));
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error looking up delivery charge for pincode $cleanCode: $e');
      return DeliveryChargeResult(
        success: false,
        pincode: cleanCode,
        ruleFound: false,
        deliveryCharge: 0.0,
        errorMessage: e.toString(),
      );
    }
    return DeliveryChargeResult(
      success: false,
      pincode: cleanCode,
      ruleFound: false,
      deliveryCharge: 0.0,
      errorMessage: 'Invalid API response format',
    );
  }

  // Fetch Wallet details from backend
  Future<Wallet?> getWallet() async {
    try {
      final response = await _apiClient.get('/api/wallets');
      if (response != null && response is List && response.isNotEmpty) {
        return Wallet.fromJson(response.first);
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching wallet: $e');
    }
    return null;
  }

  // Submit Payout request to backend
  Future<bool> requestPayout(double amount) async {
    try {
      await _apiClient.post('/api/data/payouts', {
        'id': 'payout_${DateTime.now().millisecondsSinceEpoch}',
        'partnerId': 'ref_user',
        'partnerName': 'User Partner',
        'partnerMobile': '',
        'amount': amount,
        'paymentMethod': 'UPI',
        'payoutDate': DateTime.now().toIso8601String(),
        'status': 'Pending Approval',
      });
      return true;
    } catch (e) {
      debugPrint('[ShoppingRepository] Error requesting payout: $e');
      return false;
    }
  }

  // --- REFERRAL & COMMISSION CLIENT METHODS (READ-ONLY CONSUMPTION) ---

  /// Fetch authenticated user's referral info, level, status, sponsor details, and commission summary
  Future<ReferralInfo?> getReferralInfo() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // 1. Primary: Partner Referral Info Endpoint
      final response = await _apiClient.get('/api/partners/referral-info');
      if (response != null && response is Map<String, dynamic>) {
        return ReferralInfo.fromJson(response);
      }

      // 2. Secondary: Dedicated Customer Endpoints (/api/customers/:customerId/earnings & /api/customers/:customerId/referrals)
      final customer = await getCurrentCustomer();
      final customerId = customer?.id ?? user.uid;

      final Map<String, dynamic> combinedPayload = {};

      // Fetch server earnings summary
      try {
        final earningsResponse = await _apiClient.get('/api/customers/$customerId/earnings');
        if (earningsResponse != null && earningsResponse is Map<String, dynamic>) {
          combinedPayload['commissionSummary'] = earningsResponse;
        }
      } catch (e) {
        debugPrint('[ShoppingRepository] Notice reading customer earnings API: $e');
      }

      // Fetch server referral downline list
      try {
        final referralsResponse = await _apiClient.get('/api/customers/$customerId/referrals');
        if (referralsResponse != null) {
          if (referralsResponse is List) {
            combinedPayload['referralCount'] = referralsResponse.length;
          } else if (referralsResponse is Map<String, dynamic>) {
            combinedPayload['referralCount'] = referralsResponse['totalReferrals'] ?? (referralsResponse['referrals'] as List?)?.length ?? 0;
          }
        }
      } catch (e) {
        debugPrint('[ShoppingRepository] Notice reading customer referrals API: $e');
      }

      // Populate identity fields from authenticated customer record
      final code = customer?.referralCode ?? customerId;
      combinedPayload['partner'] = {
        'referralCode': code,
        'referralLink': 'https://violeafy.com/ref/$code',
        'status': 'Active',
        'level': customer?.tier ?? 'Bronze',
      };
      if (customer?.partnerName != null && customer!.partnerName!.isNotEmpty) {
        combinedPayload['sponsor'] = {
          'id': customer.referralCode ?? '',
          'name': customer.partnerName!,
          'status': 'Active',
        };
      }

      return ReferralInfo.fromJson(combinedPayload);
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching referral info via API: $e');
    }
    return null;
  }

  /// Fetch authenticated user's 5-level commission transaction history (Read-only display)
  Future<List<CommissionHistoryItem>> getCommissionHistory() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      // 1. Primary: Partner Commission History Endpoint
      final response = await _apiClient.get('/api/partners/commission-history');
      if (response != null && response is List) {
        return response.map((item) => CommissionHistoryItem.fromJson(item as Map<String, dynamic>)).toList();
      }

      // 2. Secondary: Customer Commission Endpoint (/api/customers/:customerId/commissions)
      final customer = await getCurrentCustomer();
      final customerId = customer?.id ?? user.uid;
      final custCommissions = await _apiClient.get('/api/customers/$customerId/commissions');
      if (custCommissions != null && custCommissions is List) {
        return custCommissions.map((item) => CommissionHistoryItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error fetching commission history via API: $e');
    }
    return [];
  }

  /// Submit user-entered referral code to existing API / customer record
  Future<bool> submitReferralCode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      // 1. Primary: Partner Apply Referral Endpoint
      final response = await _apiClient.post('/api/partners/apply-referral', {
        'referralCode': cleanCode,
      });
      if (response != null && (response['success'] == true || response['status'] == 'success')) {
        return true;
      }

      // 2. Secondary: Customer Referral Endpoint (/api/customers/:customerId/referrals)
      final customer = await getCurrentCustomer();
      final customerId = customer?.id ?? user.uid;
      final custResponse = await _apiClient.post('/api/customers/$customerId/referrals', {
        'referralCode': cleanCode,
      });
      if (custResponse != null && (custResponse['success'] == true || custResponse['status'] == 'success')) {
        return true;
      }
    } catch (e) {
      debugPrint('[ShoppingRepository] Error submitting referral code via API: $e');
    }
    return false;
  }
}

