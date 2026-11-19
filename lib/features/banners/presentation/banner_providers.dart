import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/app_providers.dart';
import '../data/banner_repository.dart';
import '../data/models/banner_models.dart';

/// Immutable query key for [dynamicBannersProvider].
@immutable
class BannerQuery {
  final BannerPageType pageType;
  final BannerPlacement placement;
  final String? pageId;

  const BannerQuery({
    this.pageType = BannerPageType.defaultValue,
    this.placement = BannerPlacement.defaultValue,
    this.pageId,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BannerQuery &&
        other.pageType == pageType &&
        other.placement == placement &&
        other.pageId == pageId;
  }

  @override
  int get hashCode => Object.hash(pageType, placement, pageId);
}

final bannerRepositoryProvider = Provider<BannerRepository?>((ref) {
  try {
    if (Firebase.apps.isEmpty) return null;
    final firestore = ref.watch(firestoreProvider);
    return BannerRepository(firestore: firestore);
  } catch (_) {
    return null;
  }
});

/// Realtime stream provider for dynamic banners scoped by [BannerQuery].
final dynamicBannersProvider =
    StreamProvider.autoDispose.family<List<DynamicBanner>, BannerQuery>((ref, query) {
  final repo = ref.watch(bannerRepositoryProvider);
  if (repo == null) {
    return Stream<List<DynamicBanner>>.value(const []);
  }
  return repo.watchBanners(
    pageType: query.pageType,
    placement: query.placement,
    pageId: query.pageId,
  );
});
