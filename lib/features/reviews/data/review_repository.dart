import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'review_models.dart';

/// Review data access through VioLeafyServer (existing ApiClient + Firebase ID token).
/// Media binaries are uploaded directly to Firebase Storage into the server-issued,
/// identity-scoped draft prefix; the server verifies every object at submission time.
class ReviewRepository {
  final ApiClient _api;
  ReviewRepository([ApiClient? api]) : _api = api ?? ApiClient();

  String _base(String productId) => '/api/products/${Uri.encodeComponent(productId)}/reviews';

  Future<ReviewSummary> getSummary(String productId) async {
    final r = await _api.get('${_base(productId)}/summary');
    return ReviewSummary.fromJson(Map<String, dynamic>.from(r));
  }

  Future<Paged<CustomerReview>> getReviews(String productId,
      {ReviewSort sort = ReviewSort.top, int? rating, String? cursor, int limit = 10}) async {
    final q = <String, String>{
      'sort': sort == ReviewSort.recent ? 'recent' : 'top',
      'limit': '$limit',
      if (rating != null) 'rating': '$rating',
      if (cursor != null) 'cursor': cursor,
    };
    final r = Map<String, dynamic>.from(await _api.get('${_base(productId)}?${Uri(queryParameters: q).query}'));
    return Paged(
      ((r['reviews'] as List?) ?? []).map((e) => CustomerReview.fromJson(Map<String, dynamic>.from(e))).toList(),
      r['nextCursor'] as String?,
    );
  }

  Future<Paged<ReviewMedia>> getMedia(String productId, {String? cursor, int limit = 12}) async {
    final q = <String, String>{'limit': '$limit', if (cursor != null) 'cursor': cursor};
    final r = Map<String, dynamic>.from(await _api.get('${_base(productId)}/media?${Uri(queryParameters: q).query}'));
    return Paged(
      ((r['media'] as List?) ?? []).map((e) => ReviewMedia.fromJson(Map<String, dynamic>.from(e))).toList(),
      r['nextCursor'] as String?,
    );
  }

  Future<ReviewEligibility> getEligibility(String productId) async {
    final r = await _api.get('${_base(productId)}/eligibility');
    return ReviewEligibility.fromJson(Map<String, dynamic>.from(r));
  }

  /// Creates (or reuses) a server draft for the selected purchase; returns reviewId + upload prefix.
  Future<({String reviewId, String uploadPrefix})> startDraft(String productId, String orderId) async {
    final r = Map<String, dynamic>.from(await _api.post('${_base(productId)}/drafts', {'orderId': orderId}));
    return (reviewId: '${r['reviewId']}', uploadPrefix: '${r['uploadPrefix']}');
  }

  Future<void> discardDraft(String productId, String reviewId) async {
    await _api.delete('${_base(productId)}/drafts/${Uri.encodeComponent(reviewId)}');
  }

  Future<Map<String, dynamic>> submit({
    required String productId,
    required String reviewId,
    required String orderId,
    required int rating,
    required String title,
    required String reviewText,
    required List<String> storagePaths,
  }) async {
    final r = await _api.post(_base(productId), {
      'reviewId': reviewId,
      'orderId': orderId,
      'rating': rating,
      'title': title,
      'reviewText': reviewText,
      'media': storagePaths.map((p) => {'storagePath': p}).toList(),
    });
    return Map<String, dynamic>.from(r);
  }

  Future<int> markHelpful(String reviewId) async {
    final r = Map<String, dynamic>.from(await _api.post('/api/reviews/${Uri.encodeComponent(reviewId)}/helpful', {}));
    return (r['helpfulCount'] as num?)?.toInt() ?? 0;
  }

  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
    final trimmed = cleaned.length > 80 ? cleaned.substring(cleaned.length - 80) : cleaned;
    return trimmed.isEmpty ? 'file' : trimmed;
  }

  static String newMediaId() {
    final rnd = Random.secure();
    return List.generate(20, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// Uploads bytes to `{uploadPrefix}{mediaId}_{safeName}` and reports progress 0..1.
  UploadTask upload({
    required String uploadPrefix,
    required String mediaId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) {
    final path = '$uploadPrefix${mediaId}_${safeFileName(fileName)}';
    return FirebaseStorage.instance.ref(path).putData(bytes, SettableMetadata(contentType: contentType));
  }
}

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) => ReviewRepository());

final reviewSummaryProvider = FutureProvider.autoDispose.family<ReviewSummary, String>(
  (ref, productId) => ref.read(reviewRepositoryProvider).getSummary(productId),
);

final reviewMediaPreviewProvider = FutureProvider.autoDispose.family<Paged<ReviewMedia>, String>(
  (ref, productId) => ref.read(reviewRepositoryProvider).getMedia(productId, limit: 12),
);
