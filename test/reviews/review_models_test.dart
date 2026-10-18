import 'package:flutter_test/flutter_test.dart';
import 'package:leafy_webapp/features/reviews/data/review_models.dart';
import 'package:leafy_webapp/features/reviews/data/review_repository.dart';
import 'package:leafy_webapp/features/reviews/presentation/write_review_screen.dart';

void main() {
  test('summary parses and tolerates zero reviews', () {
    final s = ReviewSummary.fromJson({
      'averageRating': 0,
      'totalRatings': 0,
      'breakdown': [for (final st in [5, 4, 3, 2, 1]) {'star': st, 'count': 0, 'percent': 0}],
      'mediaCount': 0,
    });
    expect(s.totalRatings, 0);
    expect(s.breakdown.length, 5);
    expect(s.breakdown.every((b) => b.percent == 0), isTrue);
  });

  test('review parses media and verified flag', () {
    final r = CustomerReview.fromJson({
      'reviewId': 'r1',
      'rating': 4,
      'reviewText': 'Great',
      'customerDisplayName': 'Ravi K.',
      'verifiedPurchase': true,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'media': [
        {'mediaId': 'm1', 'reviewId': 'r1', 'type': 'video', 'url': 'https://x'}
      ],
    });
    expect(r.verifiedPurchase, isTrue);
    expect(r.media.single.isVideo, isTrue);
    expect(r.createdAt, isNotNull);
  });

  test('eligibility exposes eligible purchases only', () {
    final e = ReviewEligibility.fromJson({
      'canReview': true,
      'purchases': [
        {'orderId': 'a', 'eligible': true, 'reviewState': 'none'},
        {'orderId': 'b', 'eligible': false, 'reviewState': 'published', 'reason': 'Already reviewed'},
      ],
    });
    expect(e.eligiblePurchases.map((p) => p.orderId), ['a']);
  });

  test('MIME inference accepts supported types and rejects others', () {
    const limits = ReviewLimits();
    expect(inferReviewMime('a.JPG', null, limits), 'image/jpeg');
    expect(inferReviewMime('clip.mov', null, limits), 'video/quicktime');
    expect(inferReviewMime('x.bin', 'image/png', limits), 'image/png');
    expect(inferReviewMime('doc.pdf', 'application/pdf', limits), isNull);
    expect(inferReviewMime('anim.gif', null, limits), isNull);
  });

  test('safe filenames match the Storage rule pattern', () {
    final name = ReviewRepository.safeFileName('my photo (1)😀.jpg');
    expect(RegExp(r'^[A-Za-z0-9._\-]{1,100}$').hasMatch(name), isTrue);
    expect(RegExp(r'^[A-Za-z0-9\-]{8,64}$').hasMatch(ReviewRepository.newMediaId()), isTrue);
  });
}
