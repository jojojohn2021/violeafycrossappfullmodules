import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_errors.dart';
import '../../../core/theme/app_colors.dart';
import '../data/review_models.dart';
import '../data/review_repository.dart';

enum _UploadState { pending, uploading, done, failed }

class _PickedMedia {
  final String id = ReviewRepository.newMediaId();
  final String name;
  final String contentType;
  final Uint8List bytes;
  final bool isVideo;
  _UploadState state = _UploadState.pending;
  double progress = 0;
  String? storagePath;

  _PickedMedia({required this.name, required this.contentType, required this.bytes, required this.isVideo});
}

/// Infers a MIME type from XFile metadata or extension (mobile pickers often omit mimeType).
String? inferReviewMime(String name, String? declared, ReviewLimits limits) {
  final all = [...limits.imageTypes, ...limits.videoTypes];
  final d = declared?.toLowerCase();
  if (d != null && all.contains(d)) return d;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp',
    'heic': 'image/heic', 'heif': 'image/heif', 'mp4': 'video/mp4', 'm4v': 'video/mp4',
    'mov': 'video/quicktime', 'webm': 'video/webm',
  };
  final m = map[ext];
  return (m != null && all.contains(m)) ? m : null;
}

/// Authenticated review form. Eligibility is fetched from — and re-verified by — the server.
class WriteReviewScreen extends ConsumerStatefulWidget {
  final String productId;
  final String productName;

  const WriteReviewScreen({super.key, required this.productId, required this.productName});

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  final _picker = ImagePicker();

  ReviewEligibility? _elig;
  Object? _loadError;
  bool _loading = true;

  String? _orderId;
  int _rating = 0;
  final List<_PickedMedia> _media = [];
  String? _draftReviewId, _draftOrderId, _uploadPrefix;
  bool _submitting = false;
  String? _formError;
  bool _showValidation = false;

  ReviewLimits get _limits => _elig?.limits ?? const ReviewLimits();
  ReviewRepository get _repo => ref.read(reviewRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadEligibility();
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadEligibility() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final e = await _repo.getEligibility(widget.productId);
      if (!mounted) return;
      setState(() {
        _elig = e;
        final eligible = e.eligiblePurchases;
        _orderId = eligible.isNotEmpty ? eligible.first.orderId : null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────── Media selection ───────────

  int get _imageCount => _media.where((m) => !m.isVideo).length;
  int get _videoCount => _media.where((m) => m.isVideo).length;

  Future<void> _addFiles(List<XFile> files, {required bool video}) async {
    final rejected = <String>[];
    for (final f in files) {
      if (video ? _videoCount >= _limits.maxVideos : _imageCount >= _limits.maxImages) {
        rejected.add('${f.name}: limit of ${video ? _limits.maxVideos : _limits.maxImages} ${video ? 'videos' : 'photos'} reached');
        continue;
      }
      final mime = inferReviewMime(f.name, f.mimeType, _limits);
      if (mime == null || mime.startsWith('video/') != video) {
        rejected.add('${f.name}: unsupported format');
        continue;
      }
      final size = await f.length();
      final max = video ? _limits.maxVideoBytes : _limits.maxImageBytes;
      if (size > max) {
        rejected.add('${f.name}: larger than ${(max / 1048576).round()} MB');
        continue;
      }
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() => _media.add(_PickedMedia(name: f.name, contentType: mime, bytes: bytes, isVideo: video)));
    }
    if (rejected.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(rejected.join('\n')),
      ));
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2560);
      await _addFiles(files, video: false);
    } catch (e) {
      debugPrint('[Reviews] photo pick failed: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final f = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      if (f != null) await _addFiles([f], video: true);
    } catch (e) {
      debugPrint('[Reviews] video pick failed: $e');
    }
  }

  // ─────────── Submission ───────────

  String? _validate() {
    if (_orderId == null) return 'Please select the purchase you are reviewing.';
    if (_rating < 1) return 'Please select a star rating.';
    final text = _text.text.trim();
    if (text.length < _limits.textMin) return 'Please write at least ${_limits.textMin} characters about the product.';
    if (text.length > _limits.textMax) return 'Your review is too long.';
    if (_title.text.trim().length > _limits.titleMax) return 'Your headline is too long.';
    return null;
  }

  Future<void> _ensureDraft() async {
    if (_draftReviewId != null && _draftOrderId == _orderId) return;
    if (_draftReviewId != null) {
      // Purchase changed: discard previous draft and re-upload under the new one.
      unawaited(_repo.discardDraft(widget.productId, _draftReviewId!).catchError((_) {}));
      for (final m in _media) {
        m.state = _UploadState.pending;
        m.progress = 0;
        m.storagePath = null;
      }
    }
    final d = await _repo.startDraft(widget.productId, _orderId!);
    _draftReviewId = d.reviewId;
    _draftOrderId = _orderId;
    _uploadPrefix = d.uploadPrefix;
  }

  Future<bool> _uploadAll() async {
    var ok = true;
    for (final m in _media.where((m) => m.state != _UploadState.done)) {
      setState(() {
        m.state = _UploadState.uploading;
        m.progress = 0;
      });
      try {
        final task = _repo.upload(
          uploadPrefix: _uploadPrefix!,
          mediaId: m.id,
          fileName: m.name,
          bytes: m.bytes,
          contentType: m.contentType,
        );
        final sub = task.snapshotEvents.listen((s) {
          if (s.totalBytes > 0 && mounted) setState(() => m.progress = s.bytesTransferred / s.totalBytes);
        });
        final snap = await task;
        await sub.cancel();
        setState(() {
          m.state = _UploadState.done;
          m.progress = 1;
          m.storagePath = snap.ref.fullPath;
        });
      } catch (e) {
        debugPrint('[Reviews] upload failed: $e');
        ok = false;
        if (mounted) setState(() => m.state = _UploadState.failed);
      }
    }
    return ok;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final err = _validate();
    setState(() {
      _showValidation = true;
      _formError = err;
    });
    if (err != null) return;

    setState(() => _submitting = true);
    try {
      await _ensureDraft();
      if (!await _uploadAll()) {
        setState(() => _formError = 'Some files failed to upload. Tap "Submit review" to retry, or remove them.');
        return;
      }
      final result = await _repo.submit(
        productId: widget.productId,
        reviewId: _draftReviewId!,
        orderId: _orderId!,
        rating: _rating,
        title: _title.text.trim(),
        reviewText: _text.text.trim(),
        storagePaths: _media.map((m) => m.storagePath!).toList(),
      );
      if (!mounted) return;
      final pending = result['status'] == 'pending';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
          title: const Text('Thank you for your review'),
          content: Text(pending
              ? 'Your review has been submitted and will appear publicly once it has been approved.'
              : 'Your review has been published.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException {
      if (!mounted) return;
      setState(() => _formError = 'Your session has expired. Please log in again.');
    } on AppException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } catch (e) {
      if (mounted) setState(() => _formError = 'Network error. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    final id = _draftReviewId;
    if (id != null) unawaited(_repo.discardDraft(widget.productId, id).catchError((_) {}));
    Navigator.of(context).pop(false);
  }

  // ─────────── UI ───────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _draftReviewId != null) {
          unawaited(_repo.discardDraft(widget.productId, _draftReviewId!).catchError((_) {}));
          _draftReviewId = null;
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Write a product review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: _submitting ? null : _cancel),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    if (_loadError != null) {
      final auth = _loadError is AuthException;
      return _Message(
        icon: auth ? Icons.lock_outline : Icons.cloud_off_outlined,
        title: auth ? 'Please log in' : 'Something went wrong',
        body: auth ? 'Log in to review products you have purchased.' : 'We could not check your purchases. Please try again.',
        actionLabel: auth ? 'Log in' : 'Retry',
        onAction: auth
            ? () => context.go('/login?redirect=${Uri.encodeComponent('/product-detail/${widget.productId}')}')
            : _loadEligibility,
      );
    }
    final e = _elig!;
    if (!e.canReview) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Message(
            icon: Icons.info_outline,
            title: 'You can\'t review this product right now',
            body: e.reason ?? 'Only verified purchasers can review this product.',
          ),
          for (final p in e.purchases) _PurchaseTile(purchase: p, selected: false, onTap: null),
        ],
      );
    }

    final eligible = e.eligiblePurchases;
    final selected = eligible.where((p) => p.orderId == _orderId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(widget.productName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        _label(eligible.length > 1 ? 'Select the purchase you are reviewing' : 'Purchase being reviewed'),
        for (final p in eligible)
          _PurchaseTile(
            purchase: p,
            selected: p.orderId == _orderId,
            onTap: _submitting ? null : () => setState(() => _orderId = p.orderId),
          ),
        if (selected?.deadline != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'You can submit this review until ${DateFormat('d MMM y, h:mm a').format(selected!.deadline!)}.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        const SizedBox(height: 22),
        _label('Overall rating'),
        Row(
          children: List.generate(5, (i) {
            final star = i + 1;
            return IconButton(
              key: ValueKey('rating-star-$star'),
              tooltip: '$star star${star > 1 ? 's' : ''}',
              iconSize: 36,
              onPressed: _submitting ? null : () => setState(() => _rating = star),
              icon: Icon(star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.ratingStar),
            );
          }),
        ),
        if (_showValidation && _rating < 1)
          const Text('Please select a rating', style: TextStyle(fontSize: 12, color: AppColors.error)),
        const SizedBox(height: 18),
        _label('Add a headline (optional)'),
        TextField(
          key: const ValueKey('review-title-field'),
          controller: _title,
          enabled: !_submitting,
          maxLength: _limits.titleMax,
          decoration: _decoration('What\'s most important to know?'),
        ),
        const SizedBox(height: 10),
        _label('Write your review'),
        TextField(
          key: const ValueKey('review-text-field'),
          controller: _text,
          enabled: !_submitting,
          minLines: 5,
          maxLines: 12,
          maxLength: _limits.textMax,
          onChanged: (_) => _showValidation ? setState(() {}) : null,
          decoration: _decoration('What did you like or dislike? How did you use this product?').copyWith(
            errorText: _showValidation && _text.text.trim().length < _limits.textMin
                ? 'At least ${_limits.textMin} characters required'
                : null,
          ),
        ),
        const SizedBox(height: 14),
        _label('Add photos and videos (optional)'),
        Text(
          'Up to ${_limits.maxImages} photos (JPEG, PNG, WebP, HEIC · max ${(_limits.maxImageBytes / 1048576).round()} MB each) '
          'and ${_limits.maxVideos} videos (MP4, MOV, WebM · max ${(_limits.maxVideoBytes / 1048576).round()} MB each).',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('add-photos-button'),
              onPressed: _submitting || _imageCount >= _limits.maxImages ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text('Photos ($_imageCount/${_limits.maxImages})'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('add-video-button'),
              onPressed: _submitting || _videoCount >= _limits.maxVideos ? null : _pickVideo,
              icon: const Icon(Icons.video_call_outlined),
              label: Text('Videos ($_videoCount/${_limits.maxVideos})'),
            ),
          ],
        ),
        if (_media.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in _media)
                _MediaPreview(
                  media: m,
                  onRemove: _submitting ? null : () => setState(() => _media.remove(m)),
                ),
            ],
          ),
        ],
        if (_formError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_formError!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('cancel-review-button'),
                onPressed: _submitting ? null : _cancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                key: const ValueKey('submit-review-button'),
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                    : const Text('Submit review', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        if (e.moderationEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Reviews are checked before they appear publicly.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
        ),
      );
}

class _PurchaseTile extends StatelessWidget {
  final EligiblePurchase purchase;
  final bool selected;
  final VoidCallback? onTap;

  const _PurchaseTile({required this.purchase, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM y');
    final p = purchase;
    final sub = <String>[
      if (p.purchaseDate != null) 'Purchased ${fmt.format(p.purchaseDate!)}',
      if (p.eligible && p.deadline != null) 'Review by ${fmt.format(p.deadline!)}',
      if (p.eligible && p.daysRemaining != null) '${p.daysRemaining} days left',
      if (!p.eligible && p.reason != null) p.reason!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? AppColors.primaryGreen : AppColors.border, width: selected ? 1.6 : 1),
        color: selected ? AppColors.primaryGreen.withValues(alpha: 0.04) : null,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          p.eligible ? (selected ? Icons.radio_button_checked : Icons.radio_button_off) : Icons.block,
          color: p.eligible ? AppColors.primaryGreen : AppColors.textMuted,
        ),
        title: Text('Order ${p.orderNumber ?? p.orderId}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final _PickedMedia media;
  final VoidCallback? onRemove;

  const _MediaPreview({required this.media, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final failed = media.state == _UploadState.failed;
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: failed ? AppColors.error : AppColors.border),
                color: media.isVideo ? const Color(0xFF1F2A20) : AppColors.secondaryBackground,
              ),
              clipBehavior: Clip.antiAlias,
              child: media.isVideo
                  ? const Center(child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 30))
                  : Image.memory(media.bytes, fit: BoxFit.cover, cacheWidth: 200,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_outlined, color: AppColors.textMuted))),
            ),
          ),
          if (media.state == _UploadState.uploading)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: media.progress,
                  minHeight: 5,
                  color: AppColors.primaryGreenLight,
                  backgroundColor: Colors.white70,
                ),
              ),
            ),
          if (media.state == _UploadState.done)
            const Positioned(left: 4, bottom: 4, child: Icon(Icons.check_circle, color: AppColors.success, size: 18)),
          if (failed)
            const Positioned(left: 4, bottom: 4, child: Icon(Icons.error, color: AppColors.error, size: 18)),
          if (onRemove != null)
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen, foregroundColor: Colors.white),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
