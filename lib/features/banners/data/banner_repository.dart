import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'models/banner_models.dart';

/// Direct Cloud Firestore + Cloud Storage repository for the `banners` collection.
/// Read-only in the consumer app; never writes, migrates, or uploads media.
class BannerRepository {
  static const String collectionName = 'banners';

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storage;
  final Map<String, String> _storageUrlCache = <String, String>{};

  BannerRepository({
    required FirebaseFirestore firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore,
        _storage = storage;

  /// Filters and sorts a list of [DynamicBanner] records for a specific
  /// [pageType], [placement], optional [pageId], and consistent [now].
  static List<DynamicBanner> filterAndSortBanners({
    required Iterable<DynamicBanner> banners,
    required BannerPageType pageType,
    required BannerPlacement placement,
    String? pageId,
    required DateTime now,
  }) {
    final normalizedTargetId = pageId?.trim().toLowerCase();
    final filtered = banners.where((b) {
      if (!b.matchesPageScope(
        targetPageType: pageType,
        targetPlacement: placement,
        targetPageId: pageId,
      )) {
        return false;
      }
      if (!b.isScheduledActive(now)) return false;
      return b.resolvedSlides.isNotEmpty;
    }).toList();

    filtered.sort((a, b) {
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;

      // Prefer page-specific banners over global (pageId == null) on sortOrder tie
      if (normalizedTargetId != null && normalizedTargetId.isNotEmpty) {
        final aSpecific = (a.pageId?.trim().toLowerCase() == normalizedTargetId) ? 0 : 1;
        final bSpecific = (b.pageId?.trim().toLowerCase() == normalizedTargetId) ? 0 : 1;
        if (aSpecific != bSpecific) return aSpecific.compareTo(bSpecific);
      }

      return a.id.compareTo(b.id);
    });

    return filtered;
  }

  /// Realtime stream of active, scheduled banners from Firestore `banners`.
  /// Automatically reflects document and media updates without an app release.
  Stream<List<DynamicBanner>> watchBanners({
    BannerPageType pageType = BannerPageType.defaultValue,
    BannerPlacement placement = BannerPlacement.defaultValue,
    String? pageId,
    DateTime Function()? nowProvider,
  }) {
    final clock = nowProvider ?? DateTime.now;
    final primaryQuery = _firestore
        .collection(collectionName)
        .where('pageType', isEqualTo: pageType.wireValue)
        .where('placement', isEqualTo: placement.wireValue)
        .where('isActive', isEqualTo: true);

    return _streamWithFallback(
      primaryQuery: primaryQuery,
      pageType: pageType,
      placement: placement,
      pageId: pageId,
      clock: clock,
    );
  }

  Stream<List<DynamicBanner>> _streamWithFallback({
    required Query<Map<String, dynamic>> primaryQuery,
    required BannerPageType pageType,
    required BannerPlacement placement,
    required String? pageId,
    required DateTime Function() clock,
  }) {
    final controller = StreamController<List<DynamicBanner>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? activeSub;
    bool usedFallback = false;

    void attachListener(Query<Map<String, dynamic>> query) {
      activeSub?.cancel();
      activeSub = query.snapshots().listen(
        (snapshot) {
          final parsed = <DynamicBanner>[];
          for (final doc in snapshot.docs) {
            try {
              parsed.add(DynamicBanner.fromFirestore(doc));
            } catch (e) {
              debugPrint('[BannerRepository] Skipping malformed banners/${doc.id}: $e');
            }
          }
          final result = filterAndSortBanners(
            banners: parsed,
            pageType: pageType,
            placement: placement,
            pageId: pageId,
            now: clock(),
          );
          if (!controller.isClosed) {
            controller.add(result);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (error is FirebaseException &&
              error.code == 'failed-precondition' &&
              !usedFallback) {
            // Missing composite index fallback: query by pageType only and filter in Dart
            usedFallback = true;
            debugPrint(
              '[BannerRepository] Missing index for banners (${pageType.wireValue}, ${placement.wireValue}); '
              'falling back to single-field pageType query.',
            );
            final fallbackQuery = _firestore
                .collection(collectionName)
                .where('pageType', isEqualTo: pageType.wireValue);
            attachListener(fallbackQuery);
            return;
          }

          debugPrint(
            '[BannerRepository] Stream error (${pageType.wireValue}/${placement.wireValue}): $error',
          );
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        },
      );
    }

    controller.onListen = () => attachListener(primaryQuery);
    controller.onCancel = () {
      activeSub?.cancel();
      activeSub = null;
    };

    return controller.stream;
  }

  /// Resolves a playable/displayable HTTPS URL for [media].
  /// Prefers [media.url] unless [forceRefreshFromStorage] is true (e.g., when
  /// an existing URL failed or expired), in which case it queries Firebase
  /// Cloud Storage via [media.storagePath].
  Future<String?> resolveMediaUrl(
    BannerMedia? media, {
    bool forceRefreshFromStorage = false,
  }) async {
    if (media == null || !media.isUsable) return null;

    if (!forceRefreshFromStorage && media.hasUrl) {
      return media.url!.trim();
    }

    final storagePath = media.storagePath?.trim();
    if (storagePath == null || storagePath.isEmpty) {
      return media.hasUrl ? media.url!.trim() : null;
    }

    if (!forceRefreshFromStorage && _storageUrlCache.containsKey(storagePath)) {
      return _storageUrlCache[storagePath];
    }

    try {
      final storage = _storage ?? FirebaseStorage.instance;
      final freshUrl = await storage.ref(storagePath).getDownloadURL();
      if (freshUrl.isNotEmpty) {
        _storageUrlCache[storagePath] = freshUrl;
        return freshUrl;
      }
    } catch (e) {
      debugPrint('[BannerRepository] Failed to resolve storagePath "$storagePath": $e');
    }

    return media.hasUrl ? media.url!.trim() : null;
  }
}
