/// Data models for the customer reviews feature (shared by Web, Android and iOS).
library;

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class RatingBreakdown {
  final int star;
  final int count;
  final int percent;
  const RatingBreakdown(this.star, this.count, this.percent);
}

class ReviewSummary {
  final double averageRating;
  final int totalRatings;
  final List<RatingBreakdown> breakdown;
  final int mediaCount;
  final bool moderationEnabled;

  const ReviewSummary({
    required this.averageRating,
    required this.totalRatings,
    required this.breakdown,
    required this.mediaCount,
    required this.moderationEnabled,
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> j) => ReviewSummary(
        averageRating: _double(j['averageRating']),
        totalRatings: _int(j['totalRatings']),
        breakdown: ((j['breakdown'] as List?) ?? [])
            .map((b) => RatingBreakdown(_int(b['star']), _int(b['count']), _int(b['percent'])))
            .toList(),
        mediaCount: _int(j['mediaCount']),
        moderationEnabled: j['moderationEnabled'] == true,
      );
}

class ReviewMedia {
  final String mediaId;
  final String reviewId;
  final String type; // image | video
  final String? url;
  final String? thumbnailUrl;
  final int? rating;
  final String? customerDisplayName;
  final String? title;

  bool get isVideo => type == 'video';

  const ReviewMedia({
    required this.mediaId,
    required this.reviewId,
    required this.type,
    this.url,
    this.thumbnailUrl,
    this.rating,
    this.customerDisplayName,
    this.title,
  });

  factory ReviewMedia.fromJson(Map<String, dynamic> j) => ReviewMedia(
        mediaId: '${j['mediaId']}',
        reviewId: '${j['reviewId'] ?? ''}',
        type: j['type'] == 'video' ? 'video' : 'image',
        url: j['url'] as String?,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        rating: j['rating'] == null ? null : _int(j['rating']),
        customerDisplayName: j['customerDisplayName'] as String?,
        title: j['title'] as String?,
      );
}

class CustomerReview {
  final String reviewId;
  final int rating;
  final String title;
  final String reviewText;
  final String customerDisplayName;
  final bool verifiedPurchase;
  final DateTime? createdAt;
  final int helpfulCount;
  final List<ReviewMedia> media;

  const CustomerReview({
    required this.reviewId,
    required this.rating,
    required this.title,
    required this.reviewText,
    required this.customerDisplayName,
    required this.verifiedPurchase,
    required this.createdAt,
    required this.helpfulCount,
    required this.media,
  });

  CustomerReview copyWith({int? helpfulCount}) => CustomerReview(
        reviewId: reviewId,
        rating: rating,
        title: title,
        reviewText: reviewText,
        customerDisplayName: customerDisplayName,
        verifiedPurchase: verifiedPurchase,
        createdAt: createdAt,
        helpfulCount: helpfulCount ?? this.helpfulCount,
        media: media,
      );

  factory CustomerReview.fromJson(Map<String, dynamic> j) => CustomerReview(
        reviewId: '${j['reviewId']}',
        rating: _int(j['rating']).clamp(1, 5),
        title: '${j['title'] ?? ''}',
        reviewText: '${j['reviewText'] ?? ''}',
        customerDisplayName: '${j['customerDisplayName'] ?? 'VioLeafy Customer'}',
        verifiedPurchase: j['verifiedPurchase'] == true,
        createdAt: _date(j['createdAt']),
        helpfulCount: _int(j['helpfulCount']),
        media: ((j['media'] as List?) ?? []).map((m) => ReviewMedia.fromJson(Map<String, dynamic>.from(m))).toList(),
      );
}

class Paged<T> {
  final List<T> items;
  final String? nextCursor;
  const Paged(this.items, this.nextCursor);
}

class EligiblePurchase {
  final String orderId;
  final String? orderNumber;
  final DateTime? purchaseDate;
  final DateTime? deadline;
  final int? daysRemaining;
  final String reviewState;
  final bool eligible;
  final String? reason;

  const EligiblePurchase({
    required this.orderId,
    this.orderNumber,
    this.purchaseDate,
    this.deadline,
    this.daysRemaining,
    required this.reviewState,
    required this.eligible,
    this.reason,
  });

  factory EligiblePurchase.fromJson(Map<String, dynamic> j) => EligiblePurchase(
        orderId: '${j['orderId']}',
        orderNumber: j['orderNumber']?.toString(),
        purchaseDate: _date(j['purchaseDate']),
        deadline: _date(j['deadline']),
        daysRemaining: j['daysRemaining'] == null ? null : _int(j['daysRemaining']),
        reviewState: '${j['reviewState'] ?? 'none'}',
        eligible: j['eligible'] == true,
        reason: j['reason']?.toString(),
      );
}

class ReviewLimits {
  final int maxImages, maxVideos, maxImageBytes, maxVideoBytes, titleMax, textMin, textMax;
  final List<String> imageTypes, videoTypes;

  const ReviewLimits({
    this.maxImages = 6,
    this.maxVideos = 2,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.maxVideoBytes = 50 * 1024 * 1024,
    this.titleMax = 120,
    this.textMin = 10,
    this.textMax = 5000,
    this.imageTypes = const ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
    this.videoTypes = const ['video/mp4', 'video/quicktime', 'video/webm'],
  });

  factory ReviewLimits.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ReviewLimits();
    return ReviewLimits(
      maxImages: _int(j['maxImages']),
      maxVideos: _int(j['maxVideos']),
      maxImageBytes: _int(j['maxImageBytes']),
      maxVideoBytes: _int(j['maxVideoBytes']),
      titleMax: _int(j['titleMax']),
      textMin: _int(j['textMin']),
      textMax: _int(j['textMax']),
      imageTypes: List<String>.from(j['imageTypes'] ?? const []),
      videoTypes: List<String>.from(j['videoTypes'] ?? const []),
    );
  }
}

class ReviewEligibility {
  final bool canReview;
  final String? reason;
  final List<EligiblePurchase> purchases;
  final bool moderationEnabled;
  final ReviewLimits limits;

  const ReviewEligibility({
    required this.canReview,
    this.reason,
    required this.purchases,
    required this.moderationEnabled,
    required this.limits,
  });

  List<EligiblePurchase> get eligiblePurchases => purchases.where((p) => p.eligible).toList();

  factory ReviewEligibility.fromJson(Map<String, dynamic> j) => ReviewEligibility(
        canReview: j['canReview'] == true,
        reason: j['reason']?.toString(),
        purchases: ((j['purchases'] as List?) ?? [])
            .map((p) => EligiblePurchase.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        moderationEnabled: j['moderationEnabled'] == true,
        limits: ReviewLimits.fromJson(j['limits'] == null ? null : Map<String, dynamic>.from(j['limits'])),
      );
}

enum ReviewSort { top, recent }
