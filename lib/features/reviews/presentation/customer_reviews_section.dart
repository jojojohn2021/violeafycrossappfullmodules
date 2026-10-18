import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../data/review_models.dart';
import '../data/review_repository.dart';
import 'review_media_viewer.dart';
import 'write_review_screen.dart';

const double _wideBreakpoint = 900;
const Color _verifiedColor = Color(0xFFB45309);

bool _isSignedInCustomer() {
  final u = firebase_auth.FirebaseAuth.instance.currentUser;
  return u != null && !u.isAnonymous;
}

/// Customer Reviews section for the Product Details page.
/// Publicly visible; only verified purchasers may submit (enforced server-side).
class CustomerReviewsSection extends ConsumerStatefulWidget {
  final String productId;
  final String productName;

  const CustomerReviewsSection({super.key, required this.productId, required this.productName});

  @override
  ConsumerState<CustomerReviewsSection> createState() => _CustomerReviewsSectionState();
}

class _CustomerReviewsSectionState extends ConsumerState<CustomerReviewsSection> {
  ReviewSort _sort = ReviewSort.top;
  int? _ratingFilter;
  final List<CustomerReview> _reviews = [];
  String? _cursor;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _reviews.clear();
    _cursor = null;
    _loadedOnce = false;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(reviewRepositoryProvider).getReviews(
            widget.productId,
            sort: _sort,
            rating: _ratingFilter,
            cursor: _cursor,
          );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _reviews.addAll(page.items);
        _cursor = page.nextCursor;
        _loadedOnce = true;
      });
    } catch (e) {
      if (mounted && seq == _requestSeq) setState(() => _error = e);
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  void _setSort(ReviewSort s) {
    if (s == _sort) return;
    _sort = s;
    _loading = false;
    _reload();
  }

  void _setFilter(int? star) {
    _ratingFilter = star == _ratingFilter ? null : star;
    _loading = false;
    _reload();
  }

  Future<void> _writeReview() async {
    if (!_isSignedInCustomer()) {
      final redirect = Uri.encodeComponent('/product-detail/${widget.productId}');
      context.go('/login?redirect=$redirect');
      return;
    }
    final submitted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WriteReviewScreen(productId: widget.productId, productName: widget.productName),
    ));
    if (submitted == true && mounted) {
      ref.invalidate(reviewSummaryProvider(widget.productId));
      ref.invalidate(reviewMediaPreviewProvider(widget.productId));
      _loading = false;
      _reload();
    }
  }

  Future<void> _markHelpful(int index) async {
    if (!_isSignedInCustomer()) {
      context.go('/login?redirect=${Uri.encodeComponent('/product-detail/${widget.productId}')}');
      return;
    }
    final review = _reviews[index];
    try {
      final count = await ref.read(reviewRepositoryProvider).markHelpful(review.reviewId);
      if (!mounted) return;
      setState(() => _reviews[index] = review.copyWith(helpfulCount: count));
      _toast('Thank you for your feedback.');
    } on AppException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not record your vote. Please try again.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= _wideBreakpoint;
      final summary = _SummaryPanel(
        productId: widget.productId,
        activeFilter: _ratingFilter,
        onFilter: _setFilter,
        onWrite: _writeReview,
      );
      final right = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MediaStrip(productId: widget.productId),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 20),
          _ReviewList(
            reviews: _reviews,
            sort: _sort,
            ratingFilter: _ratingFilter,
            loading: _loading,
            loadedOnce: _loadedOnce,
            error: _error,
            hasMore: _cursor != null,
            onSort: _setSort,
            onClearFilter: () => _setFilter(_ratingFilter),
            onLoadMore: _loadMore,
            onRetry: () {
              _loading = false;
              _loadedOnce ? _loadMore() : _reload();
            },
            onHelpful: _markHelpful,
          ),
        ],
      );

      return Container(
        key: const ValueKey('customer-reviews-section'),
        margin: const EdgeInsets.only(top: 28),
        padding: const EdgeInsets.only(top: 24),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 330, child: summary),
                  const SizedBox(width: 40),
                  Expanded(child: right),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 20), const Divider(height: 1, color: AppColors.border), const SizedBox(height: 20), right],
              ),
      );
    });
  }
}

// ─────────────────────────────── Stars ───────────────────────────────

class StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const StarRow({super.key, required this.rating, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5 stars',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final v = rating - i;
            final icon = v >= 0.75 ? Icons.star_rounded : (v >= 0.25 ? Icons.star_half_rounded : Icons.star_outline_rounded);
            return Icon(icon, size: size, color: AppColors.ratingStar);
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Summary ───────────────────────────────

class _SummaryPanel extends ConsumerWidget {
  final String productId;
  final int? activeFilter;
  final ValueChanged<int?> onFilter;
  final VoidCallback onWrite;

  const _SummaryPanel({required this.productId, required this.activeFilter, required this.onFilter, required this.onWrite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(reviewSummaryProvider(productId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Customer reviews',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        summaryAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LinearProgressIndicator(color: AppColors.primaryGreen, backgroundColor: AppColors.border),
          ),
          error: (e, _) => _InlineError(
            message: 'Ratings could not be loaded.',
            onRetry: () => ref.invalidate(reviewSummaryProvider(productId)),
          ),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StarRow(rating: s.averageRating, size: 22),
                  const SizedBox(width: 8),
                  Text(s.totalRatings == 0 ? 'No ratings yet' : '${s.averageRating.toStringAsFixed(1)} out of 5',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${NumberFormat.decimalPattern('en_IN').format(s.totalRatings)} ${s.totalRatings == 1 ? 'rating' : 'ratings'}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              for (final b in s.breakdown)
                _DistributionBar(
                  breakdown: b,
                  active: activeFilter == b.star,
                  onTap: b.count > 0 || activeFilter == b.star ? () => onFilter(b.star) : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: const ExpansionTile(
            key: ValueKey('ratings-calculation-tile'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: 12),
            iconColor: AppColors.primaryGreen,
            collapsedIconColor: AppColors.textSecondary,
            title: Text('How are ratings calculated?',
                style: TextStyle(fontSize: 13, color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
            children: [
              Text(
                'The overall rating is the simple average of all published ratings from customers who bought this '
                'product on VioLeafy. Each verified purchase can be reviewed once within 60 days of purchase. '
                'Reviews that are pending moderation or have been rejected are not counted.',
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 24, color: AppColors.border),
        const Text('Review this product',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Share your thoughts with other customers',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: OutlinedButton(
            key: const ValueKey('write-review-button'),
            onPressed: onWrite,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.textMuted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
            ),
            child: const Text('Write a product review', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  final RatingBreakdown breakdown;
  final bool active;
  final VoidCallback? onTap;

  const _DistributionBar({required this.breakdown, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 13,
      color: onTap != null ? AppColors.primaryGreen : AppColors.textSecondary,
      fontWeight: active ? FontWeight.bold : FontWeight.w500,
    );
    return Semantics(
      button: onTap != null,
      label: '${breakdown.star} star, ${breakdown.percent} percent',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(
            children: [
              SizedBox(width: 48, child: Text('${breakdown.star} star', style: labelStyle)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: active ? AppColors.primaryGreen : const Color(0xFFD5D9D9)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: breakdown.percent / 100),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(color: AppColors.ratingStar),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text('${breakdown.percent}%', textAlign: TextAlign.right, style: labelStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Media ───────────────────────────────

class _MediaStrip extends ConsumerWidget {
  final String productId;
  const _MediaStrip({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(reviewMediaPreviewProvider(productId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Customer photos and videos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            if (mediaAsync.asData?.value.items.isNotEmpty == true)
              TextButton(
                key: const ValueKey('see-all-media-button'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AllReviewMediaScreen(productId: productId),
                )),
                child: const Text('See all', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        mediaAsync.when(
          loading: () => SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => Container(
                width: 96,
                decoration: BoxDecoration(color: AppColors.shimmerBase, borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          error: (e, _) => _InlineError(
            message: 'Customer media could not be loaded.',
            onRetry: () => ref.invalidate(reviewMediaPreviewProvider(productId)),
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return const _EmptyNote(icon: Icons.photo_library_outlined, text: 'No customer photos or videos yet.');
            }
            final items = page.items;
            return SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => ReviewMediaThumb(
                  media: items[i],
                  onTap: () => ReviewMediaViewer.show(context, items, i),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// "See all" gallery with server-side pagination.
class AllReviewMediaScreen extends ConsumerStatefulWidget {
  final String productId;
  const AllReviewMediaScreen({super.key, required this.productId});

  @override
  ConsumerState<AllReviewMediaScreen> createState() => _AllReviewMediaScreenState();
}

class _AllReviewMediaScreenState extends ConsumerState<AllReviewMediaScreen> {
  final List<ReviewMedia> _items = [];
  String? _cursor;
  bool _loading = false, _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(reviewRepositoryProvider).getMedia(widget.productId, cursor: _cursor, limit: 24);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Customer photos and videos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _load();
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160, mainAxisSpacing: 10, crossAxisSpacing: 10),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => LayoutBuilder(
                    builder: (_, c) => ReviewMediaThumb(
                      media: _items[i],
                      size: c.maxWidth,
                      onTap: () => ReviewMediaViewer.show(context, _items, i),
                    ),
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: _error != null
                      ? _InlineError(message: 'Could not load more media.', onRetry: _load)
                      : _loading
                          ? const CircularProgressIndicator(color: AppColors.primaryGreen)
                          : (_items.isEmpty
                              ? const _EmptyNote(icon: Icons.photo_library_outlined, text: 'No customer photos or videos yet.')
                              : const SizedBox.shrink()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Review list ───────────────────────────────

class _ReviewList extends StatelessWidget {
  final List<CustomerReview> reviews;
  final ReviewSort sort;
  final int? ratingFilter;
  final bool loading, loadedOnce, hasMore;
  final Object? error;
  final ValueChanged<ReviewSort> onSort;
  final VoidCallback onClearFilter, onLoadMore, onRetry;
  final ValueChanged<int> onHelpful;

  const _ReviewList({
    required this.reviews,
    required this.sort,
    required this.ratingFilter,
    required this.loading,
    required this.loadedOnce,
    required this.hasMore,
    required this.error,
    required this.onSort,
    required this.onClearFilter,
    required this.onLoadMore,
    required this.onRetry,
    required this.onHelpful,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(sort == ReviewSort.top ? 'Top reviews from India' : 'Most recent reviews from India',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.secondaryBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ReviewSort>(
                  key: const ValueKey('review-sort-dropdown'),
                  value: sort,
                  isDense: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(value: ReviewSort.top, child: Text('Top reviews')),
                    DropdownMenuItem(value: ReviewSort.recent, child: Text('Most recent')),
                  ],
                  onChanged: (v) => v == null ? null : onSort(v),
                ),
              ),
            ),
          ],
        ),
        if (ratingFilter != null) ...[
          const SizedBox(height: 10),
          InputChip(
            label: Text('$ratingFilter star reviews only'),
            onDeleted: onClearFilter,
            deleteIconColor: AppColors.textSecondary,
            backgroundColor: AppColors.secondaryBackground,
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < reviews.length; i++) ...[
          _ReviewCard(review: reviews[i], onHelpful: () => onHelpful(i)),
          if (i < reviews.length - 1) const Divider(height: 28, color: AppColors.border),
        ],
        if (error != null)
          _InlineError(message: 'Reviews could not be loaded.', onRetry: onRetry)
        else if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen, strokeWidth: 2.5)),
          )
        else if (loadedOnce && reviews.isEmpty)
          _EmptyNote(
            icon: Icons.rate_review_outlined,
            text: ratingFilter == null
                ? 'There are no customer reviews yet. Bought this product? Be the first to review it.'
                : 'No $ratingFilter-star reviews yet.',
          )
        else if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              key: const ValueKey('load-more-reviews-button'),
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('See more reviews'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                side: const BorderSide(color: AppColors.primaryGreen),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final CustomerReview review;
  final VoidCallback onHelpful;
  const _ReviewCard({required this.review, required this.onHelpful});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final long = r.reviewText.length > 320;
    final initial = r.customerDisplayName.isNotEmpty ? r.customerDisplayName[0].toUpperCase() : 'V';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
              child: Text(initial, style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(r.customerDisplayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            StarRow(rating: r.rating.toDouble(), size: 17),
            if (r.title.isNotEmpty)
              Text(r.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 4),
        if (r.createdAt != null)
          Text('Reviewed in India on ${DateFormat('d MMMM y').format(r.createdAt!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (r.verifiedPurchase) ...[
          const SizedBox(height: 4),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: _verifiedColor),
              SizedBox(width: 4),
              Text('Verified Purchase', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _verifiedColor)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          r.reviewText,
          maxLines: long && !_expanded ? 6 : null,
          overflow: long && !_expanded ? TextOverflow.ellipsis : TextOverflow.visible,
          style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary),
        ),
        if (long)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Read less' : 'Read more', style: const TextStyle(color: AppColors.primaryGreen)),
          ),
        if (r.media.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < r.media.length; i++)
                ReviewMediaThumb(
                  media: r.media[i],
                  size: 76,
                  onTap: () => ReviewMediaViewer.show(context, r.media, i),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            if (r.helpfulCount > 0)
              Text('${r.helpfulCount} ${r.helpfulCount == 1 ? 'person' : 'people'} found this helpful',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            OutlinedButton(
              onPressed: widget.onHelpful,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Helpful', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────── Shared bits ───────────────────────────────

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Flexible(child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          TextButton(onPressed: onRetry, child: const Text('Retry', style: TextStyle(color: AppColors.primaryGreen))),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.secondaryBackground, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}
