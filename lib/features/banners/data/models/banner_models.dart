import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported page types in the Firestore `banners` collection.
enum BannerPageType {
  home('home'),
  category('category'),
  product('product'),
  other('other');

  final String wireValue;
  const BannerPageType(this.wireValue);

  /// Default pageType for a new or unspecified banner configuration.
  static const BannerPageType defaultValue = BannerPageType.home;

  /// Strictly parses an existing Firestore document value.
  /// Returns `null` when missing or unknown so records are never silently
  /// displayed on the wrong page.
  static BannerPageType? tryParse(dynamic raw) {
    if (raw == null) return null;
    final normalized = raw.toString().trim().toLowerCase();
    for (final value in values) {
      if (value.wireValue == normalized) return value;
    }
    return null;
  }
}

/// Supported banner placements in the Firestore `banners` collection.
enum BannerPlacement {
  hero('hero'),
  secondary('secondary'),
  strip('strip'),
  spotlight('spotlight'),
  footerPromo('footer_promo');

  final String wireValue;
  const BannerPlacement(this.wireValue);

  /// Default placement for a new or unspecified banner configuration.
  static const BannerPlacement defaultValue = BannerPlacement.hero;

  /// Strictly parses an existing Firestore document value.
  /// Returns `null` when missing or unknown so records are never injected
  /// into an unintended slot.
  static BannerPlacement? tryParse(dynamic raw) {
    if (raw == null) return null;
    final normalized = raw.toString().trim().toLowerCase();
    for (final value in values) {
      if (value.wireValue == normalized) return value;
    }
    return null;
  }
}

/// Supported media types for banner slides and top-level assets.
enum BannerMediaType {
  image('image'),
  video('video');

  final String wireValue;
  const BannerMediaType(this.wireValue);

  static BannerMediaType? tryParse(dynamic raw, {String? fallbackMimeType}) {
    if (raw != null) {
      final normalized = raw.toString().trim().toLowerCase();
      if (normalized == 'video' || normalized.startsWith('video/')) {
        return BannerMediaType.video;
      }
      if (normalized == 'image' || normalized.startsWith('image/')) {
        return BannerMediaType.image;
      }
    }
    if (fallbackMimeType != null) {
      final mime = fallbackMimeType.trim().toLowerCase();
      if (mime.startsWith('video/')) return BannerMediaType.video;
      if (mime.startsWith('image/')) return BannerMediaType.image;
    }
    return null;
  }
}

DateTime? parseBannerTimestamp(dynamic raw) {
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate().toUtc();
  if (raw is DateTime) return raw.toUtc();
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(raw.round(), isUtc: true);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed)?.toUtc();
  }
  if (raw is Map) {
    final seconds = raw['_seconds'] ?? raw['seconds'];
    final nanos = raw['_nanoseconds'] ?? raw['nanoseconds'] ?? 0;
    if (seconds is num) {
      final ms = (seconds.toInt() * 1000) + ((nanos is num ? nanos.toInt() : 0) ~/ 1000000);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
  }
  return null;
}

String? _cleanString(dynamic raw) {
  if (raw == null) return null;
  final trimmed = raw.toString().trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
  return trimmed;
}

int? _parseInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString().trim());
}

double? _parseDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().trim());
}

bool _parseBool(dynamic raw, {required bool fallback}) {
  if (raw is bool) return raw;
  if (raw is String) {
    final lower = raw.trim().toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return fallback;
}

/// Media variant metadata for desktop/mobile images, videos, or posters.
class BannerMedia {
  final String? url;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? sizeBytes;
  final double? durationSec;

  const BannerMedia({
    this.url,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.width,
    this.height,
    this.sizeBytes,
    this.durationSec,
  });

  bool get hasUrl => url != null && url!.trim().isNotEmpty;
  bool get hasStoragePath => storagePath != null && storagePath!.trim().isNotEmpty;
  bool get isUsable => hasUrl || hasStoragePath;

  bool get isVideoMime =>
      mimeType != null && mimeType!.trim().toLowerCase().startsWith('video/');

  static BannerMedia? fromMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final cleaned = _cleanString(raw);
      if (cleaned == null) return null;
      return BannerMedia(url: cleaned);
    }
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final media = BannerMedia(
      url: _cleanString(map['url']),
      storagePath: _cleanString(map['storagePath']),
      fileName: _cleanString(map['fileName']),
      mimeType: _cleanString(map['mimeType']),
      width: _parseInt(map['width']),
      height: _parseInt(map['height']),
      sizeBytes: _parseInt(map['sizeBytes']),
      durationSec: _parseDouble(map['durationSec']),
    );
    return media.isUsable ? media : null;
  }
}

/// Optional call-to-action button metadata.
class BannerCTA {
  final String label;
  final String route;

  const BannerCTA({
    required this.label,
    required this.route,
  });

  bool get isValid => label.trim().isNotEmpty && route.trim().isNotEmpty;

  static BannerCTA? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final label = _cleanString(map['label']);
    final route = _cleanString(map['route']);
    if (label == null || route == null) return null;
    return BannerCTA(label: label, route: route);
  }
}

/// Placement specification defaults matching the verified Firestore schema.
class BannerPlacementSpec {
  final String desktopAspectRatio;
  final String mobileAspectRatio;
  final int slideDurationSec;
  final int maxImageSizeMb;
  final int maxVideoSizeMb;

  const BannerPlacementSpec({
    this.desktopAspectRatio = '8:3',
    this.mobileAspectRatio = '4:5',
    this.slideDurationSec = 6,
    this.maxImageSizeMb = 10,
    this.maxVideoSizeMb = 15,
  });

  double get desktopRatioValue =>
      parseAspectRatio(desktopAspectRatio, fallback: 8 / 3);

  double get mobileRatioValue =>
      parseAspectRatio(mobileAspectRatio, fallback: 4 / 5);

  static double parseAspectRatio(String ratio, {required double fallback}) {
    final parts = ratio.split(':');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w != null && h != null && w > 0 && h > 0) {
        return w / h;
      }
    }
    final single = double.tryParse(ratio.trim());
    if (single != null && single > 0) return single;
    return fallback;
  }

  factory BannerPlacementSpec.fromMap(dynamic raw) {
    if (raw is! Map) return const BannerPlacementSpec();
    final map = Map<String, dynamic>.from(raw);
    final duration = _parseInt(map['slideDurationSec']);
    return BannerPlacementSpec(
      desktopAspectRatio: _cleanString(map['desktopAspectRatio']) ?? '8:3',
      mobileAspectRatio: _cleanString(map['mobileAspectRatio']) ?? '4:5',
      slideDurationSec: (duration != null && duration > 0) ? duration : 6,
      maxImageSizeMb: _parseInt(map['maxImageSizeMb']) ?? 10,
      maxVideoSizeMb: _parseInt(map['maxVideoSizeMb']) ?? 15,
    );
  }
}

/// Single slide inside a carousel (or synthesized from top-level media).
class BannerSlide {
  final String id;
  final BannerMediaType mediaType;
  final BannerMedia? desktop;
  final BannerMedia? mobile;
  final BannerMedia? desktopPoster;
  final BannerMedia? mobilePoster;
  final int? slideDurationSec;
  final int sortOrder;
  final String? title;
  final String? subtitle;
  final BannerCTA? cta;

  const BannerSlide({
    required this.id,
    required this.mediaType,
    this.desktop,
    this.mobile,
    this.desktopPoster,
    this.mobilePoster,
    this.slideDurationSec,
    this.sortOrder = 0,
    this.title,
    this.subtitle,
    this.cta,
  });

  bool get hasUsableMedia =>
      (desktop != null && desktop!.isUsable) ||
      (mobile != null && mobile!.isUsable);

  /// Selects desktop media on wide screens and mobile media on narrow screens,
  /// falling back to the available variant when one is absent.
  BannerMedia? selectMedia({required bool isDesktop}) {
    if (isDesktop) {
      if (desktop != null && desktop!.isUsable) return desktop;
      if (mobile != null && mobile!.isUsable) return mobile;
      return null;
    } else {
      if (mobile != null && mobile!.isUsable) return mobile;
      if (desktop != null && desktop!.isUsable) return desktop;
      return null;
    }
  }

  /// Selects slide poster for the active viewport.
  /// Top-level banner posters are used ONLY when [allowTopLevelPosterFallback]
  /// is explicitly enabled.
  BannerMedia? selectPoster({
    required bool isDesktop,
    BannerMedia? topLevelDesktopPoster,
    BannerMedia? topLevelMobilePoster,
    bool allowTopLevelPosterFallback = false,
  }) {
    if (isDesktop) {
      if (desktopPoster != null && desktopPoster!.isUsable) return desktopPoster;
      if (mobilePoster != null && mobilePoster!.isUsable) return mobilePoster;
      if (allowTopLevelPosterFallback) {
        if (topLevelDesktopPoster != null && topLevelDesktopPoster.isUsable) {
          return topLevelDesktopPoster;
        }
        if (topLevelMobilePoster != null && topLevelMobilePoster.isUsable) {
          return topLevelMobilePoster;
        }
      }
      return null;
    } else {
      if (mobilePoster != null && mobilePoster!.isUsable) return mobilePoster;
      if (desktopPoster != null && desktopPoster!.isUsable) return desktopPoster;
      if (allowTopLevelPosterFallback) {
        if (topLevelMobilePoster != null && topLevelMobilePoster.isUsable) {
          return topLevelMobilePoster;
        }
        if (topLevelDesktopPoster != null && topLevelDesktopPoster.isUsable) {
          return topLevelDesktopPoster;
        }
      }
      return null;
    }
  }

  /// Resolves the effective slide duration in seconds.
  int effectiveDurationSec({required int defaultSlideDurationSec}) {
    if (slideDurationSec != null && slideDurationSec! > 0) {
      return slideDurationSec!;
    }
    return defaultSlideDurationSec > 0 ? defaultSlideDurationSec : 6;
  }

  static BannerSlide? fromMap(dynamic raw, {required int index}) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final desktop = BannerMedia.fromMap(map['desktop']);
    final mobile = BannerMedia.fromMap(map['mobile']);
    if (desktop == null && mobile == null) return null;

    final inferredType = BannerMediaType.tryParse(
          map['mediaType'],
          fallbackMimeType: desktop?.mimeType ?? mobile?.mimeType,
        ) ??
        BannerMediaType.image;

    final duration = _parseInt(map['slideDurationSec']);
    return BannerSlide(
      id: _cleanString(map['id']) ?? 'slide_$index',
      mediaType: inferredType,
      desktop: desktop,
      mobile: mobile,
      desktopPoster: BannerMedia.fromMap(map['desktopPoster']),
      mobilePoster: BannerMedia.fromMap(map['mobilePoster']),
      slideDurationSec: (duration != null && duration > 0) ? duration : null,
      sortOrder: _parseInt(map['sortOrder']) ?? index,
      title: _cleanString(map['title']),
      subtitle: _cleanString(map['subtitle']),
      cta: BannerCTA.fromMap(map['cta']),
    );
  }
}

/// Typed representation of a document in the Firestore `banners` collection.
class DynamicBanner {
  final String id;
  final BannerPageType? pageType;
  final String? pageId;
  final BannerPlacement? placement;
  final int sortOrder;

  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;

  final bool carouselEnabled;
  final bool autoplay;
  final bool loop;

  final BannerMediaType mediaType;
  final BannerMedia? desktop;
  final BannerMedia? mobile;
  final BannerMedia? desktopPoster;
  final BannerMedia? mobilePoster;

  final List<BannerSlide> slides;
  final String? title;
  final String? subtitle;
  final BannerCTA? cta;
  final BannerPlacementSpec placementSpec;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const DynamicBanner({
    required this.id,
    required this.pageType,
    this.pageId,
    required this.placement,
    this.sortOrder = 0,
    this.isActive = false,
    this.startsAt,
    this.endsAt,
    this.carouselEnabled = false,
    this.autoplay = true,
    this.loop = true,
    this.mediaType = BannerMediaType.image,
    this.desktop,
    this.mobile,
    this.desktopPoster,
    this.mobilePoster,
    this.slides = const [],
    this.title,
    this.subtitle,
    this.cta,
    this.placementSpec = const BannerPlacementSpec(),
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  /// Returns `true` only when `isActive` is true and [now] falls within
  /// `[startsAt, endsAt]` (when present).
  bool isScheduledActive(DateTime now) {
    if (!isActive) return false;
    final utcNow = now.toUtc();
    if (startsAt != null && utcNow.isBefore(startsAt!)) return false;
    if (endsAt != null && utcNow.isAfter(endsAt!)) return false;
    return true;
  }

  /// Checks whether this banner belongs to [targetPageType], [targetPlacement],
  /// and [targetPageId] (including global `pageId == null` banners).
  /// Documents with missing or unknown `pageType` or `placement` return `false`.
  bool matchesPageScope({
    required BannerPageType targetPageType,
    required BannerPlacement targetPlacement,
    String? targetPageId,
  }) {
    if (pageType == null || placement == null) return false;
    if (pageType != targetPageType || placement != targetPlacement) return false;

    final normalizedTargetId = _cleanString(targetPageId)?.toLowerCase();
    final normalizedDocPageId = _cleanString(pageId)?.toLowerCase();

    if (normalizedTargetId == null) {
      // Only global records (pageId == null) match when no specific pageId is requested
      return normalizedDocPageId == null;
    }

    // When a specific pageId is requested, match exact pageId OR global (pageId == null)
    return normalizedDocPageId == null || normalizedDocPageId == normalizedTargetId;
  }

  /// Resolves the ordered list of slides to render.
  /// - When `carouselEnabled` is true and `slides` is non-empty, returns ONLY
  ///   sorted usable slides (never duplicating top-level desktop/mobile).
  /// - Otherwise synthesizes a single slide from top-level `desktop`/`mobile`.
  List<BannerSlide> get resolvedSlides {
    if (carouselEnabled && slides.isNotEmpty) {
      final indexed = slides
          .asMap()
          .entries
          .where((e) => e.value.hasUsableMedia)
          .toList()
        ..sort((a, b) {
          final cmp = a.value.sortOrder.compareTo(b.value.sortOrder);
          return cmp != 0 ? cmp : a.key.compareTo(b.key);
        });
      if (indexed.isNotEmpty) {
        return indexed.map((e) => e.value).toList(growable: false);
      }
    }

    if ((desktop != null && desktop!.isUsable) ||
        (mobile != null && mobile!.isUsable)) {
      return [
        BannerSlide(
          id: id,
          mediaType: mediaType,
          desktop: desktop,
          mobile: mobile,
          desktopPoster: desktopPoster,
          mobilePoster: mobilePoster,
          slideDurationSec: placementSpec.slideDurationSec,
          sortOrder: sortOrder,
          title: title,
          subtitle: subtitle,
          cta: cta,
        ),
      ];
    }

    return const [];
  }

  factory DynamicBanner.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return DynamicBanner.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  factory DynamicBanner.fromMap(String documentId, Map<String, dynamic> map) {
    final desktop = BannerMedia.fromMap(map['desktop']);
    final mobile = BannerMedia.fromMap(map['mobile']);
    final desktopPoster = BannerMedia.fromMap(map['desktopPoster']);
    final mobilePoster = BannerMedia.fromMap(map['mobilePoster']);

    final rawSlides = map['slides'];
    final parsedSlides = <BannerSlide>[];
    if (rawSlides is List) {
      for (var i = 0; i < rawSlides.length; i++) {
        final slide = BannerSlide.fromMap(rawSlides[i], index: i);
        if (slide != null) parsedSlides.add(slide);
      }
    }

    // Placement spec can be nested under `placementSpec` or flat at top level
    final rawSpec = <String, dynamic>{
      if (map['desktopAspectRatio'] != null)
        'desktopAspectRatio': map['desktopAspectRatio'],
      if (map['mobileAspectRatio'] != null)
        'mobileAspectRatio': map['mobileAspectRatio'],
      if (map['slideDurationSec'] != null)
        'slideDurationSec': map['slideDurationSec'],
      if (map['maxImageSizeMb'] != null)
        'maxImageSizeMb': map['maxImageSizeMb'],
      if (map['maxVideoSizeMb'] != null)
        'maxVideoSizeMb': map['maxVideoSizeMb'],
      if (map['placementSpec'] is Map)
        ...Map<String, dynamic>.from(map['placementSpec'] as Map),
    };

    final inferredMediaType = BannerMediaType.tryParse(
          map['mediaType'],
          fallbackMimeType: desktop?.mimeType ?? mobile?.mimeType,
        ) ??
        BannerMediaType.image;

    return DynamicBanner(
      id: documentId,
      pageType: BannerPageType.tryParse(map['pageType']),
      pageId: _cleanString(map['pageId']),
      placement: BannerPlacement.tryParse(map['placement']),
      sortOrder: _parseInt(map['sortOrder']) ?? 0,
      isActive: _parseBool(map['isActive'], fallback: false),
      startsAt: parseBannerTimestamp(map['startsAt']),
      endsAt: parseBannerTimestamp(map['endsAt']),
      carouselEnabled: _parseBool(map['carouselEnabled'], fallback: false),
      autoplay: _parseBool(map['autoplay'], fallback: true),
      loop: _parseBool(map['loop'], fallback: true),
      mediaType: inferredMediaType,
      desktop: desktop,
      mobile: mobile,
      desktopPoster: desktopPoster,
      mobilePoster: mobilePoster,
      slides: parsedSlides,
      title: _cleanString(map['title']),
      subtitle: _cleanString(map['subtitle']),
      cta: BannerCTA.fromMap(map['cta']),
      placementSpec: BannerPlacementSpec.fromMap(rawSpec),
      createdAt: parseBannerTimestamp(map['createdAt']),
      updatedAt: parseBannerTimestamp(map['updatedAt']),
      createdBy: _cleanString(map['createdBy']),
      updatedBy: _cleanString(map['updatedBy']),
    );
  }
}
