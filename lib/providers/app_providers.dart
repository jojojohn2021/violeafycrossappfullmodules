import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/config/env_config.dart';
import '../core/network/api_client.dart';
import '../models/models.dart';
import '../repositories/shopping_repository.dart';

// Firestore Provider (Pointing to native 'violeafydb' with fallback to default database)
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  try {
    return FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: EnvConfig.firestoreDatabaseId,
    );
  } catch (e) {
    return FirebaseFirestore.instance;
  }
});

// Repository Provider
final shoppingRepositoryProvider = Provider<ShoppingRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ShoppingRepository(firestore: firestore);
});

// Products FutureProvider (Live API / MongoDB)
final productsProvider = FutureProvider<List<ProductPerformance>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getProducts();
});

// Category Models FutureProvider (Authoritative Server API)
final categoryModelsProvider = FutureProvider<List<ProductCategory>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getCategoryModels();
});

// Categories String FutureProvider (Authoritative Server API)
final categoriesProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getCategories();
});

// Brand Models FutureProvider (Authoritative Server API)
final brandModelsProvider = FutureProvider<List<ProductBrand>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getBrandModels();
});

// Brand Owner Models FutureProvider (Authoritative Server API)
final brandOwnerModelsProvider = FutureProvider<List<ProductBrandOwner>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getBrandOwnerModels();
});

// Firestore Image Retriever Family FutureProvider
final firestoreImageProvider = FutureProvider.family<String?, ({String collection, String docIdOrRef})>((ref, arg) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getFirestoreImageUrl(arg.collection, arg.docIdOrRef);
});

// Banners FutureProvider (Live API / MongoDB)
final bannersProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getBanners();
});

// Active Coupons FutureProvider (used to show/hide the cart's Apply Coupon section)
final couponsProvider = FutureProvider<List<Coupon>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getCoupons();
});

// Authentication State Provider
final authStateProvider = StreamProvider<firebase_auth.User?>((ref) {
  return firebase_auth.FirebaseAuth.instance.authStateChanges();
});

// Sales Orders FutureProvider (Live API / MongoDB) - Bounded to Auth User State
final salesOrdersProvider = FutureProvider<List<SalesOrder>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getSalesOrders();
});

// Wallet FutureProvider (Live API / MongoDB) - Bounded to Auth User State
final walletProvider = FutureProvider<Wallet?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getWallet();
});

final leadsProvider = FutureProvider<List<Lead>>((ref) async {
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getLeads();
});

final currentUserCustomerProvider = FutureProvider<CustomerPerformance?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getCurrentCustomer();
});

// Referral Info FutureProvider (Read-only partner level, referral code/link, sponsor, commission summary)
final referralInfoProvider = FutureProvider<ReferralInfo?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getReferralInfo();
});

// 5-Level Commission History FutureProvider (Read-only transaction list)
final commissionHistoryProvider = FutureProvider<List<CommissionHistoryItem>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(shoppingRepositoryProvider);
  return repo.getCommissionHistory();
});


// Filter & Search States
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');
final searchQueryProvider = StateProvider<String>((ref) => '');

// Filtered Products Provider
final filteredProductsProvider = Provider<List<ProductPerformance>>((ref) {
  final productsAsync = ref.watch(productsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  return productsAsync.maybeWhen(
    data: (products) {
      return products.where((p) {
        final matchesCategory = (category == 'All') ||
            (p.category?.toLowerCase() == category.toLowerCase());
        final matchesQuery = query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query) ||
            (p.description != null && p.description!.toLowerCase().contains(query));
        return matchesCategory && matchesQuery;
      }).toList();
    },
    orElse: () => [],
  );
});

// Wishlist StateNotifier
class WishlistNotifier extends StateNotifier<List<String>> {
  final ShoppingRepository _repo;

  WishlistNotifier(this._repo) : super([]) {
    state = _repo.getWishlistIds();
  }

  void toggle(String productId) {
    _repo.toggleWishlist(productId);
    state = List.from(_repo.getWishlistIds());
  }

  bool contains(String productId) => state.contains(productId);
}

final wishlistProvider = StateNotifierProvider<WishlistNotifier, List<String>>((ref) {
  final repo = ref.watch(shoppingRepositoryProvider);
  return WishlistNotifier(repo);
});

// Cart StateNotifier
class CartNotifier extends StateNotifier<List<SalesProduct>> {
  final ShoppingRepository _repo;

  CartNotifier(this._repo) : super([]) {
    state = _repo.getCartItems();
  }

  void addToCart(ProductPerformance product, {int quantity = 1}) {
    _repo.addToCart(product, quantity: quantity);
    state = List.from(_repo.getCartItems());
  }

  void removeFromCart(String productId) {
    _repo.removeFromCart(productId);
    state = List.from(_repo.getCartItems());
  }

  void updateQuantity(String productId, int newQuantity) {
    _repo.updateQuantity(productId, newQuantity);
    state = List.from(_repo.getCartItems());
  }

  void clearCart() {
    _repo.clearCart();
    state = [];
  }

  double get totalPrice {
    return state.fold(0, (total, item) => total + (item.price * item.quantity));
  }

  int get totalItemCount {
    return state.fold(0, (total, item) => total + item.quantity);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<SalesProduct>>((ref) {
  final repo = ref.watch(shoppingRepositoryProvider);
  return CartNotifier(repo);
});

// OTP Login State & Notifier (Persists state across deep link redirects)
class OtpState {
  final String phone;
  final String? verificationId;
  final bool codeSent;
  final bool isLoading;
  final String? errorMessage;
  final int? resendToken;

  const OtpState({
    this.phone = '',
    this.verificationId,
    this.codeSent = false,
    this.isLoading = false,
    this.errorMessage,
    this.resendToken,
  });

  OtpState copyWith({
    String? phone,
    String? verificationId,
    bool? codeSent,
    bool? isLoading,
    String? errorMessage,
    int? resendToken,
  }) {
    return OtpState(
      phone: phone ?? this.phone,
      verificationId: verificationId ?? this.verificationId,
      codeSent: codeSent ?? this.codeSent,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      resendToken: resendToken ?? this.resendToken,
    );
  }
}

class OtpNotifier extends StateNotifier<OtpState> {
  OtpNotifier() : super(const OtpState()) {
    debugPrint('[OtpNotifier] Initialized');
  }

  void setPhone(String phone) {
    debugPrint('[OtpNotifier] setPhone: $phone');
    state = state.copyWith(phone: phone);
  }

  void reset() {
    debugPrint('[OtpNotifier] reset called');
    state = const OtpState();
  }

  Future<void> sendOtp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final cleanPhone = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    debugPrint('[OtpNotifier] sendOtp called for: $cleanPhone');
    if (cleanPhone.length != 10) {
      state = state.copyWith(errorMessage: 'Please enter a valid 10-digit mobile number');
      return;
    }

    state = state.copyWith(phone: cleanPhone, isLoading: true, errorMessage: null);

    try {
      debugPrint('[OtpNotifier] triggering verifyPhoneNumber with 60s timeout');
      await firebase_auth.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$cleanPhone',
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          debugPrint('[OtpNotifier] verificationCompleted (Auto-verify)');
          try {
            await firebase_auth.FirebaseAuth.instance.signInWithCredential(credential);
            final response = await ApiClient().post('/api/auth/verify-login', {});
            if (response != null && response['success'] == true) {
              state = state.copyWith(isLoading: false);
              debugPrint('[OtpNotifier] Auto-verify & backend verification success');
            } else {
              final errorMsg = response?['error'] ?? 'Backend verification failed';
              state = state.copyWith(isLoading: false, errorMessage: errorMsg);
            }
          } catch (e) {
            state = state.copyWith(isLoading: false, errorMessage: 'Auto-verification failed: $e');
            debugPrint('[OtpNotifier] Auto-verify sign-in failed: $e');
          }
        },
        verificationFailed: (e) {
          debugPrint('[OtpNotifier] verificationFailed: ${e.code} - ${e.message}');
          state = state.copyWith(
            isLoading: false,
            errorMessage: _phoneAuthError(e),
          );
        },
        codeSent: (verificationId, resendToken) {
          debugPrint('[OtpNotifier] codeSent: $verificationId');
          state = state.copyWith(
            verificationId: verificationId,
            codeSent: true,
            isLoading: false,
            resendToken: resendToken,
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
          debugPrint('[OtpNotifier] codeAutoRetrievalTimeout (timeout reached): $verificationId');
          state = state.copyWith(
            verificationId: verificationId,
            isLoading: false,
          );
        },
        forceResendingToken: state.resendToken,
      );
    } catch (e) {
      debugPrint('[OtpNotifier] Exception in verifyPhoneNumber: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error starting verification: $e',
      );
    }
  }

  String _phoneAuthError(firebase_auth.FirebaseAuthException error) {
    switch (error.code) {
      case 'auth/network-request-failed':
        return 'Firebase could not reach the verification service. Check your internet connection and confirm localhost is enabled in Firebase Console > Authentication > Settings > Authorized domains.';
      case 'auth/too-many-requests':
        return 'Too many verification attempts. Wait a few minutes before requesting another OTP.';
      case 'auth/invalid-phone-number':
        return 'Enter a valid 10-digit Indian mobile number.';
      case 'auth/quota-exceeded':
        return 'SMS verification quota exceeded for this Firebase project. Try again later or use a configured test number.';
      case 'auth/captcha-check-failed':
      case 'auth/invalid-app-credential':
        return 'Phone verification could not validate this web app. Add localhost to Firebase Authentication authorized domains and reload the page.';
      default:
        return 'Verification failed (${error.code}). ${error.message ?? 'Check Firebase Phone provider and authorized domains.'}';
    }
  }

  Future<bool> verifyOtp(String otp) async {
    final cleanOtp = otp.trim();
    if (cleanOtp.length < 6) {
      state = state.copyWith(errorMessage: 'Please enter a 6-digit OTP code');
      return false;
    }

    if (state.verificationId == null) {
      state = state.copyWith(errorMessage: 'Verification ID missing. Please resend OTP.');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: state.verificationId!,
        smsCode: cleanOtp,
      );
      await firebase_auth.FirebaseAuth.instance.signInWithCredential(credential);

      // Perform single backend login verification call
      final response = await ApiClient().post('/api/auth/verify-login', {});
      if (response != null && response['success'] == true) {
        state = state.copyWith(isLoading: false);
        debugPrint('[OtpNotifier] Backend login verification succeeded: ${response['action']} - customerId: ${response['customerId']}');
        return true;
      } else {
        final errorMsg = response?['error'] ?? 'Backend verification failed. Please try again.';
        state = state.copyWith(isLoading: false, errorMessage: errorMsg);
        return false;
      }
    } catch (e) {
      debugPrint('[OtpNotifier] Verification error: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'Verification failed: $e');
      return false;
    }
  }
}

final otpLoginProvider = StateNotifierProvider<OtpNotifier, OtpState>((ref) {
  return OtpNotifier();
});

class PayUEnvironmentNotifier extends StateNotifier<String> {
  PayUEnvironmentNotifier() : super(kReleaseMode ? 'Production' : 'Test') {
    _load();
  }

  Future<void> _load() async {
    final env = await EnvConfig.getPayUEnvironment();
    state = env;
  }

  Future<void> toggleEnvironment() async {
    final nextEnv = state == 'Production' ? 'Test' : 'Production';
    state = nextEnv;
    await EnvConfig.setPayUEnvironment(nextEnv);
  }

  Future<void> setEnvironment(String env) async {
    if (env != 'Test' && env != 'Production') return;
    state = env;
    await EnvConfig.setPayUEnvironment(env);
  }
}

final payuEnvironmentProvider = StateNotifierProvider<PayUEnvironmentNotifier, String>((ref) {
  return PayUEnvironmentNotifier();
});

// Reuses the existing users/{uid}.role Firestore field already relied upon by firestore.rules' isAdmin().
final isAdminUserProvider = FutureProvider<bool>((ref) async {
  final user = firebase_auth.FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final firestore = ref.watch(firestoreProvider);
    final doc = await firestore.collection('users').doc(user.uid).get();
    return doc.exists && doc.data()?['role'] == 'Admin';
  } catch (e) {
    debugPrint('[isAdminUserProvider] role lookup failed: $e');
    return false;
  }
});

// PayU Debug Diagnostics toggle - persisted server-side via payment_gateway_settings (payu_debug_enabled).
// Observation-only: never affects PayU credentials, hash, or payment logic. Defaults ON.
class PayUDebugNotifier extends StateNotifier<bool> {
  final ApiClient _apiClient;

  PayUDebugNotifier({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient(), super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _apiClient.get('/api/payment/debug-settings');
      if (response is Map) {
        state = response['payu_debug_enabled'] != false;
      }
    } catch (e) {
      debugPrint('[PayUDebugNotifier] Failed to load debug setting: $e');
    }
  }

  Future<void> toggle() async {
    final next = !state;
    try {
      final response = await _apiClient.post('/api/payment/debug-settings', {'enabled': next});
      if (response is Map && response['success'] == true) {
        state = response['payu_debug_enabled'] == true;
      }
    } catch (e) {
      debugPrint('[PayUDebugNotifier] Failed to update debug setting: $e');
    }
  }
}

final payuDebugProvider = StateNotifierProvider<PayUDebugNotifier, bool>((ref) {
  return PayUDebugNotifier();
});

// PayU Payment testing toggle (Home Page top bar) - visible to ALL logged-in users, no admin/role
// restriction. ON (true, default) runs the normal PayU flow unchanged; OFF bypasses PayU and asks the
// backend to process the transaction via the same successful-payment path used by a real PayU success.
// The backend is authoritative and only honors the bypass outside the Production environment.
class PayUEnabledNotifier extends StateNotifier<bool> {
  final ApiClient _apiClient;

  PayUEnabledNotifier({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient(), super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _apiClient.get('/api/payment/payu-toggle');
      if (response is Map) {
        state = response['payu_enabled'] != false;
      }
    } catch (e) {
      debugPrint('[PayUEnabledNotifier] Failed to load PayU toggle setting: $e');
    }
  }

  Future<void> toggle() async {
    final next = !state;
    try {
      final response = await _apiClient.post('/api/payment/payu-toggle', {'enabled': next});
      if (response is Map && response['success'] == true) {
        state = response['payu_enabled'] != false;
      }
    } catch (e) {
      debugPrint('[PayUEnabledNotifier] Failed to update PayU toggle setting: $e');
    }
  }
}

final payuEnabledProvider = StateNotifierProvider<PayUEnabledNotifier, bool>((ref) {
  return PayUEnabledNotifier();
});

