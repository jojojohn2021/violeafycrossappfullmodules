/**
 * Customer Reviews, Ratings, Photos & Videos — VioLeafyServer module.
 *
 * Collections:
 *   customer_reviews/{reviewId}                 – review documents (auto IDs)
 *   customer_reviews/{reviewId}/helpful_votes/{uid}
 *   customer_review_aggregates/{productId}      – server-maintained public aggregates
 *
 * Status lifecycle: draft -> (pending | published) -> (published | rejected)
 *   "draft" reserves a reviewId for the authorised media-upload flow; drafts are never public.
 *
 * Purchase eligibility is derived ONLY from existing sales_orders records, using the server's
 * existing customer/order ownership mapping (fetchUserScopedSalesOrders).
 */
import type { Express } from 'express';
import { FieldValue, Timestamp, type Firestore, type Transaction } from 'firebase-admin/firestore';
import type { Storage } from 'firebase-admin/storage';

export interface ReviewDeps {
  adminDb: Firestore;
  adminStorage: Storage;
  getAuthenticatedUser: (req: any) => Promise<any>;
  fetchUserScopedSalesOrders: (user: any) => Promise<any[]>;
  findCustomerByAuthUser: (user: any) => Promise<any | null>;
}

// ───────────────────────────── Configuration ─────────────────────────────
const envInt = (k: string, d: number) => {
  const v = parseInt(process.env[k] || '', 10);
  return Number.isFinite(v) && v > 0 ? v : d;
};

export const REVIEW_CONFIG = {
  windowDays: 60,
  timezoneOffsetMinutes: 330, // Asia/Kolkata (IST) calendar-day boundary
  moderationEnabled: String(process.env.REVIEW_MODERATION_ENABLED || '').toLowerCase() === 'true',
  maxImages: envInt('REVIEW_MAX_IMAGES', 6),
  maxVideos: envInt('REVIEW_MAX_VIDEOS', 2),
  maxImageBytes: envInt('REVIEW_MAX_IMAGE_BYTES', 8 * 1024 * 1024),
  maxVideoBytes: envInt('REVIEW_MAX_VIDEO_BYTES', 50 * 1024 * 1024),
  titleMax: 120,
  textMin: 10,
  textMax: 5000,
  pageSizeDefault: 10,
  pageSizeMax: 30,
  signedUrlTtlMs: 2 * 60 * 60 * 1000,
  draftTtlHours: 24,
  rejectedRetentionDays: envInt('REVIEW_REJECTED_RETENTION_DAYS', 30),
};

export const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];
export const VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'];

const REVIEWS = 'customer_reviews';
const AGGREGATES = 'customer_review_aggregates';
const ID_RE = /^[A-Za-z0-9_\-]{1,128}$/;

// ───────────────────────────── Pure helpers (unit-tested) ─────────────────────────────

/** Parses an order date stored as ISO string, Firestore Timestamp, epoch ms or {_seconds}. */
export function parseOrderDate(v: any): Date | null {
  if (!v) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v;
  if (typeof v.toDate === 'function') return v.toDate();
  if (typeof v === 'object' && typeof v._seconds === 'number') return new Date(v._seconds * 1000);
  if (typeof v === 'object' && typeof v.seconds === 'number') return new Date(v.seconds * 1000);
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

/**
 * Deadline = end of the 60th calendar day after the purchase date (IST calendar days).
 * Purchase on 1 Jan (IST) -> deadline 2 Mar 23:59:59.999 IST (non-leap year).
 */
export function computeReviewDeadline(purchaseDate: Date, cfg = REVIEW_CONFIG): Date {
  const off = cfg.timezoneOffsetMinutes * 60000;
  const local = new Date(purchaseDate.getTime() + off);
  const endLocal = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + cfg.windowDays, 23, 59, 59, 999);
  return new Date(endLocal - off);
}

const lc = (v: any) => String(v ?? '').trim().toLowerCase();

/** Maps the existing order lifecycle (orderStatus / deliveryStatus) to review qualification. */
export function orderLifecycleState(order: any): { qualifies: boolean; reason?: string } {
  const statuses = [lc(order.orderStatus), lc(order.deliveryStatus), lc(order.status)];
  if (statuses.some(s => s.includes('cancel'))) return { qualifies: false, reason: 'This order was cancelled.' };
  if (statuses.some(s => s === 'returned' || s === 'fully returned' || s === 'refunded' || s === 'rto')) {
    return { qualifies: false, reason: 'This order was returned.' };
  }
  const delivered = statuses.some(s => s === 'delivered' || s === 'completed');
  if (!delivered) return { qualifies: false, reason: 'You can review this product once your order has been delivered.' };
  return { qualifies: true };
}

/** Finds order lines containing the exact product ID. Order items live in order.products[]. */
export function findProductLines(order: any, productId: string): Array<{ item: any; index: number; orderItemId: string }> {
  const items = Array.isArray(order.products) ? order.products
    : Array.isArray(order.orderPayload?.products) ? order.orderPayload.products : [];
  const out: Array<{ item: any; index: number; orderItemId: string }> = [];
  items.forEach((item: any, index: number) => {
    const pid = String(item?.productId ?? item?.id ?? '').trim();
    if (pid && pid === productId) {
      const existingId = item.orderItemId || item.itemId || item.lineId;
      out.push({ item, index, orderItemId: String(existingId || `line-${index}`) });
    }
  });
  return out;
}

/** Strips tags/control characters and collapses excessive whitespace. */
export function sanitizeText(v: any, max: number): string {
  return String(v ?? '')
    .replace(/<[^>]*>/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
    .slice(0, max);
}

/** Ranking: helpfulness first, then content quality (media, length). Rating is never a factor. */
export function computeRankScore(helpfulCount: number, mediaCount: number, textLength: number): number {
  return helpfulCount * 10 + (mediaCount > 0 ? 3 : 0) + Math.min(Math.floor(textLength / 150), 3);
}

/** Public display name: first name + last initial; never phone/email. */
export function safeDisplayName(customer: any, user: any): string {
  const raw = sanitizeText(customer?.name || customer?.customerName || customer?.fullName ||
    [customer?.firstName, customer?.lastName].filter(Boolean).join(' ') || user?.name || '', 80);
  if (!raw || /\d{5,}|@/.test(raw)) return 'VioLeafy Customer';
  const parts = raw.split(/\s+/).filter(Boolean);
  return parts.length > 1 ? `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.` : parts[0];
}

export function buildSummary(agg: any) {
  const dist = agg?.distribution || {};
  const total = Math.max(0, Number(agg?.ratingCount || 0));
  const sum = Math.max(0, Number(agg?.ratingSum || 0));
  const breakdown = [5, 4, 3, 2, 1].map(star => {
    const count = Math.max(0, Number(dist[String(star)] || 0));
    return { star, count, percent: total > 0 ? Math.round((count / total) * 100) : 0 };
  });
  return {
    averageRating: total > 0 ? Math.round((sum / total) * 10) / 10 : 0,
    totalRatings: total,
    breakdown,
    mediaCount: Math.max(0, Number(agg?.mediaCount || 0)),
  };
}

/** Detects the media family from file magic bytes. */
export function sniffMime(buf: Buffer): string | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.slice(0, 4).toString('ascii') === 'RIFF' && buf.slice(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
  if (buf.length >= 4 && buf[0] === 0x1a && buf[1] === 0x45 && buf[2] === 0xdf && buf[3] === 0xa3) return 'video/webm';
  if (buf.length >= 12 && buf.slice(4, 8).toString('ascii') === 'ftyp') {
    const brand = buf.slice(8, 12).toString('ascii');
    if (['heic', 'heix', 'hevc', 'heim', 'heis'].includes(brand)) return 'image/heic';
    if (['mif1', 'msf1', 'heif'].includes(brand)) return 'image/heif';
    if (brand === 'qt  ') return 'video/quicktime';
    return 'video/mp4';
  }
  return null;
}

/** Declared vs. detected compatibility (mp4/quicktime share the ISO-BMFF container). */
export function mimeCompatible(declared: string, sniffed: string | null): boolean {
  if (!sniffed) return false;
  if (declared === sniffed) return true;
  const iso = ['video/mp4', 'video/quicktime'];
  if (iso.includes(declared) && iso.includes(sniffed)) return true;
  const heif = ['image/heic', 'image/heif'];
  return heif.includes(declared) && heif.includes(sniffed);
}

// ───────────────────────────── Rate limiting (per instance) ─────────────────────────────
const buckets = new Map<string, number[]>();
function rateLimited(key: string, max: number, windowMs: number): boolean {
  const now = Date.now();
  const hits = (buckets.get(key) || []).filter(t => now - t < windowMs);
  if (hits.length >= max) { buckets.set(key, hits); return true; }
  hits.push(now);
  buckets.set(key, hits);
  return false;
}

// ───────────────────────────── Module ─────────────────────────────
export function registerCustomerReviewRoutes(app: Express, deps: ReviewDeps) {
  const { adminDb, adminStorage, getAuthenticatedUser, fetchUserScopedSalesOrders, findCustomerByAuthUser } = deps;
  const bucket = () => adminStorage.bucket();

  const isAnon = (u: any) => !u || u.firebase?.sign_in_provider === 'anonymous' || u.provider_id === 'anonymous';

  async function productExists(productId: string): Promise<boolean> {
    if (!ID_RE.test(productId)) return false;
    const snap = await adminDb.collection('products').doc(productId).get();
    return snap.exists;
  }

  async function signUrl(path?: string | null): Promise<string | null> {
    if (!path) return null;
    try {
      const [url] = await bucket().file(path).getSignedUrl({ action: 'read', expires: Date.now() + REVIEW_CONFIG.signedUrlTtlMs });
      return url;
    } catch (err: any) {
      console.warn('[Reviews] Signed URL generation failed:', err?.code || err?.message);
      return null;
    }
  }

  async function publicMedia(review: any) {
    const media = Array.isArray(review.media) ? review.media : [];
    return Promise.all(media.map(async (m: any) => ({
      mediaId: m.mediaId,
      reviewId: review.reviewId,
      type: m.type,
      contentType: m.contentType,
      url: await signUrl(m.storagePath),
      thumbnailUrl: await signUrl(m.thumbnailPath),
    })));
  }

  const toIso = (v: any) => parseOrderDate(v)?.toISOString() ?? null;

  async function publicReview(r: any) {
    return {
      reviewId: r.reviewId,
      rating: r.rating,
      title: r.title || '',
      reviewText: r.reviewText,
      customerDisplayName: r.customerDisplayName || 'VioLeafy Customer',
      verifiedPurchase: r.verifiedPurchase === true,
      createdAt: toIso(r.createdAt),
      helpfulCount: r.helpfulCount || 0,
      media: await publicMedia(r),
    };
  }

  /** Builds per-purchase eligibility from authoritative orders + existing review state. */
  async function computeEligibility(user: any, productId: string, now = new Date()) {
    const orders = await fetchUserScopedSalesOrders(user);
    const existingSnap = await adminDb.collection(REVIEWS)
      .where('userUid', '==', user.uid).where('productId', '==', productId).get();
    const byOrder = new Map<string, any>();
    existingSnap.docs.forEach(d => byOrder.set(String(d.get('orderId')), { id: d.id, ...d.data() }));

    const purchases: any[] = [];
    for (const order of orders) {
      const lines = findProductLines(order, productId);
      if (lines.length === 0) continue;
      const orderId = String(order.id);
      const purchaseDate = parseOrderDate(order.createdAt || order.orderDate || order.date);
      const existing = byOrder.get(orderId);
      const entry: any = {
        orderId,
        orderNumber: order.orderNumber || null,
        orderItemId: lines[0].orderItemId,
        purchaseDate: purchaseDate?.toISOString() ?? null,
        deadline: null,
        daysRemaining: null,
        reviewState: existing ? existing.status : 'none',
        reviewId: existing ? existing.id : null,
        eligible: false,
        reason: null as string | null,
      };
      if (!purchaseDate) { entry.reason = 'The purchase date for this order is unavailable.'; purchases.push(entry); continue; }
      const deadline = computeReviewDeadline(purchaseDate);
      entry.deadline = deadline.toISOString();
      entry.daysRemaining = Math.max(0, Math.ceil((deadline.getTime() - now.getTime()) / 86400000));
      const life = orderLifecycleState(order);
      if (existing && existing.status !== 'draft') entry.reason = 'You have already reviewed this purchase.';
      else if (!life.qualifies) entry.reason = life.reason!;
      else if (now.getTime() > deadline.getTime()) entry.reason = 'The 60-day review period for this purchase has ended.';
      else entry.eligible = true;
      purchases.push(entry);
    }
    purchases.sort((a, b) => String(b.purchaseDate).localeCompare(String(a.purchaseDate)));
    const eligible = purchases.filter(p => p.eligible);
    let reason: string | null = null;
    if (eligible.length === 0) {
      reason = purchases.length === 0
        ? 'Only customers who have purchased this product can write a review.'
        : (purchases[0].reason || 'No eligible purchase found.');
    }
    return { canReview: eligible.length > 0, reason, purchases, orders };
  }

  async function requireUser(req: any, res: any) {
    const user = await getAuthenticatedUser(req);
    if (isAnon(user)) {
      res.status(401).json({ error: 'Please log in to continue.' });
      return null;
    }
    return user;
  }

  /** Applies a published-state change to the aggregate inside a transaction. */
  function aggregateDelta(tx: Transaction, aggSnap: FirebaseFirestore.DocumentSnapshot, productId: string,
    before: { rating: number; mediaCount: number } | null, after: { rating: number; mediaCount: number } | null) {
    const cur = aggSnap.exists ? aggSnap.data()! : {};
    const dist: Record<string, number> = { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, ...(cur.distribution || {}) };
    let count = Number(cur.ratingCount || 0), sum = Number(cur.ratingSum || 0), media = Number(cur.mediaCount || 0);
    if (before) { count--; sum -= before.rating; media -= before.mediaCount; dist[String(before.rating)]--; }
    if (after) { count++; sum += after.rating; media += after.mediaCount; dist[String(after.rating)]++; }
    count = Math.max(0, count); sum = Math.max(0, sum); media = Math.max(0, media);
    Object.keys(dist).forEach(k => { dist[k] = Math.max(0, dist[k]); });
    tx.set(aggSnap.ref, {
      productId, ratingCount: count, ratingSum: sum, distribution: dist, mediaCount: media,
      averageRating: count > 0 ? Math.round((sum / count) * 10) / 10 : 0,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  async function deletePrefix(prefix: string, keep: Set<string> = new Set()) {
    try {
      const [files] = await bucket().getFiles({ prefix });
      await Promise.all(files.filter(f => !keep.has(f.name)).map(f => f.delete({ ignoreNotFound: true })));
    } catch (err: any) {
      console.warn('[Reviews] Storage cleanup failed for prefix', prefix, err?.message);
    }
  }

  const uploadPrefix = (uid: string, productId: string, reviewId: string) => `customer_reviews/${uid}/${productId}/${reviewId}/`;

  const validateProductParam = async (req: any, res: any): Promise<string | null> => {
    const productId = String(req.params.productId || '').trim();
    if (!ID_RE.test(productId)) { res.status(400).json({ error: 'Invalid product ID.' }); return null; }
    if (!(await productExists(productId))) { res.status(404).json({ error: 'Product not found.' }); return null; }
    return productId;
  };

  // ─────────── Public: summary ───────────
  app.get('/api/products/:productId/reviews/summary', async (req, res) => {
    try {
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const agg = await adminDb.collection(AGGREGATES).doc(productId).get();
      res.json({ productId, ...buildSummary(agg.exists ? agg.data() : null), moderationEnabled: REVIEW_CONFIG.moderationEnabled });
    } catch (err: any) {
      console.error('[Reviews] summary failed:', err?.message);
      res.status(500).json({ error: 'Failed to load review summary.' });
    }
  });

  async function cursorQuery(base: FirebaseFirestore.Query, cursor: any) {
    if (cursor && ID_RE.test(String(cursor))) {
      const snap = await adminDb.collection(REVIEWS).doc(String(cursor)).get();
      if (snap.exists) return base.startAfter(snap);
    }
    return base;
  }

  // ─────────── Public: review list ───────────
  app.get('/api/products/:productId/reviews', async (req, res) => {
    try {
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const limit = Math.min(Math.max(parseInt(String(req.query.limit || ''), 10) || REVIEW_CONFIG.pageSizeDefault, 1), REVIEW_CONFIG.pageSizeMax);
      const sort = req.query.sort === 'recent' ? 'recent' : 'top';
      const rating = parseInt(String(req.query.rating || ''), 10);
      let q: FirebaseFirestore.Query = adminDb.collection(REVIEWS).where('productId', '==', productId).where('status', '==', 'published');
      if (rating >= 1 && rating <= 5) q = q.where('rating', '==', rating);
      q = sort === 'recent' ? q.orderBy('createdAt', 'desc') : q.orderBy('rankScore', 'desc').orderBy('createdAt', 'desc');
      q = (await cursorQuery(q, req.query.cursor)).limit(limit + 1);
      const snap = await q.get();
      const docs = snap.docs.slice(0, limit);
      const reviews = await Promise.all(docs.map(d => publicReview({ reviewId: d.id, ...d.data() })));
      res.json({ reviews, sort, nextCursor: snap.docs.length > limit ? docs[docs.length - 1].id : null });
    } catch (err: any) {
      console.error('[Reviews] list failed:', err?.message);
      res.status(500).json({ error: 'Failed to load reviews.' });
    }
  });

  // ─────────── Public: media gallery ───────────
  app.get('/api/products/:productId/reviews/media', async (req, res) => {
    try {
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const limit = Math.min(Math.max(parseInt(String(req.query.limit || ''), 10) || 12, 1), 30);
      let q: FirebaseFirestore.Query = adminDb.collection(REVIEWS)
        .where('productId', '==', productId).where('status', '==', 'published').where('hasMedia', '==', true)
        .orderBy('createdAt', 'desc');
      q = (await cursorQuery(q, req.query.cursor)).limit(limit + 1);
      const snap = await q.get();
      const docs = snap.docs.slice(0, limit);
      const groups = await Promise.all(docs.map(async d => {
        const r: any = { reviewId: d.id, ...d.data() };
        const media = await publicMedia(r);
        return media.map(m => ({ ...m, rating: r.rating, customerDisplayName: r.customerDisplayName, title: r.title || '' }));
      }));
      res.json({ media: groups.flat(), nextCursor: snap.docs.length > limit ? docs[docs.length - 1].id : null });
    } catch (err: any) {
      console.error('[Reviews] media failed:', err?.message);
      res.status(500).json({ error: 'Failed to load customer media.' });
    }
  });

  // ─────────── Authenticated: eligibility ───────────
  app.get('/api/products/:productId/reviews/eligibility', async (req, res) => {
    try {
      const user = await requireUser(req, res);
      if (!user) return;
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const { canReview, reason, purchases } = await computeEligibility(user, productId);
      res.json({
        productId, canReview, reason, purchases,
        moderationEnabled: REVIEW_CONFIG.moderationEnabled,
        limits: {
          maxImages: REVIEW_CONFIG.maxImages, maxVideos: REVIEW_CONFIG.maxVideos,
          maxImageBytes: REVIEW_CONFIG.maxImageBytes, maxVideoBytes: REVIEW_CONFIG.maxVideoBytes,
          imageTypes: IMAGE_TYPES, videoTypes: VIDEO_TYPES,
          titleMax: REVIEW_CONFIG.titleMax, textMin: REVIEW_CONFIG.textMin, textMax: REVIEW_CONFIG.textMax,
        },
      });
    } catch (err: any) {
      console.error('[Reviews] eligibility failed:', err?.message);
      res.status(500).json({ error: 'Failed to check review eligibility.' });
    }
  });

  // ─────────── Authenticated: create/reuse a draft (authorised upload session) ───────────
  app.post('/api/products/:productId/reviews/drafts', async (req, res) => {
    try {
      const user = await requireUser(req, res);
      if (!user) return;
      if (rateLimited(`draft:${user.uid}`, 20, 3600000)) return res.status(429).json({ error: 'Too many requests. Please try again later.' });
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const orderId = String(req.body?.orderId || '').trim();
      const elig = await computeEligibility(user, productId);
      const purchase = elig.purchases.find(p => p.orderId === orderId);
      if (!purchase) return res.status(403).json({ error: 'This purchase is not associated with your account.' });
      if (!purchase.eligible) return res.status(403).json({ error: purchase.reason || 'This purchase is not eligible for review.' });

      const reviewId = await adminDb.runTransaction(async tx => {
        const dupSnap = await tx.get(adminDb.collection(REVIEWS)
          .where('userUid', '==', user.uid).where('productId', '==', productId).where('orderId', '==', orderId).limit(1));
        if (!dupSnap.empty) {
          const d = dupSnap.docs[0];
          if (d.get('status') !== 'draft') throw Object.assign(new Error('You have already reviewed this purchase.'), { http: 409 });
          return d.id;
        }
        const ref = adminDb.collection(REVIEWS).doc();
        tx.create(ref, {
          reviewId: ref.id, productId, userUid: user.uid, orderId, orderItemId: purchase.orderItemId,
          status: 'draft', verifiedPurchase: false, media: [], mediaCount: 0, hasMedia: false, helpfulCount: 0, rankScore: 0,
          createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
        return ref.id;
      });
      res.json({ reviewId, uploadPrefix: uploadPrefix(user.uid, productId, reviewId), deadline: purchase.deadline });
    } catch (err: any) {
      if (err?.http) return res.status(err.http).json({ error: err.message });
      console.error('[Reviews] draft failed:', err?.message);
      res.status(500).json({ error: 'Failed to start review.' });
    }
  });

  // ─────────── Authenticated: discard a draft (cleans up uploaded media) ───────────
  app.delete('/api/products/:productId/reviews/drafts/:reviewId', async (req, res) => {
    try {
      const user = await requireUser(req, res);
      if (!user) return;
      const productId = String(req.params.productId || ''), reviewId = String(req.params.reviewId || '');
      if (!ID_RE.test(productId) || !ID_RE.test(reviewId)) return res.status(400).json({ error: 'Invalid identifier.' });
      const ref = adminDb.collection(REVIEWS).doc(reviewId);
      const snap = await ref.get();
      if (!snap.exists || snap.get('userUid') !== user.uid || snap.get('productId') !== productId) return res.status(404).json({ error: 'Draft not found.' });
      if (snap.get('status') !== 'draft') return res.status(409).json({ error: 'Submitted reviews cannot be discarded here.' });
      await deletePrefix(uploadPrefix(user.uid, productId, reviewId));
      await ref.delete();
      res.json({ success: true });
    } catch (err: any) {
      console.error('[Reviews] draft delete failed:', err?.message);
      res.status(500).json({ error: 'Failed to discard draft.' });
    }
  });

  /** Verifies an uploaded object's ownership, path, size, declared and actual type. */
  async function verifyMedia(path: string, prefix: string) {
    if (typeof path !== 'string' || !path.startsWith(prefix) || path.includes('..')) throw new Error('A media file does not belong to this review.');
    const name = path.slice(prefix.length);
    const m = /^([A-Za-z0-9\-]{8,64})_([A-Za-z0-9._\-]{1,100})$/.exec(name);
    if (!m) throw new Error('Invalid media file name.');
    const file = bucket().file(path);
    const [exists] = await file.exists();
    if (!exists) throw new Error('A media file failed to upload. Please retry.');
    const [meta] = await file.getMetadata();
    const contentType = String(meta.contentType || '').toLowerCase();
    const size = Number(meta.size || 0);
    const type = IMAGE_TYPES.includes(contentType) ? 'image' : VIDEO_TYPES.includes(contentType) ? 'video' : null;
    if (!type) throw new Error('Unsupported media format.');
    const max = type === 'image' ? REVIEW_CONFIG.maxImageBytes : REVIEW_CONFIG.maxVideoBytes;
    if (size <= 0 || size > max) throw new Error(`A ${type} exceeds the ${Math.round(max / 1048576)} MB limit.`);
    const [head] = await file.download({ start: 0, end: 31 });
    if (!mimeCompatible(contentType, sniffMime(head))) throw new Error('A media file content does not match its type.');
    return { mediaId: m[1], type, storagePath: path, contentType, fileName: m[2], sizeBytes: size, createdAt: Timestamp.now(), thumbnailPath: null };
  }

  // ─────────── Authenticated: submit review ───────────
  app.post('/api/products/:productId/reviews', async (req, res) => {
    try {
      const user = await requireUser(req, res);
      if (!user) return;
      if (rateLimited(`submit:${user.uid}`, 10, 3600000)) return res.status(429).json({ error: 'Too many submissions. Please try again later.' });
      const productId = await validateProductParam(req, res);
      if (!productId) return;
      const body = req.body || {};
      const reviewId = String(body.reviewId || '').trim();
      const orderId = String(body.orderId || '').trim();
      if (!ID_RE.test(reviewId)) return res.status(400).json({ error: 'Invalid review reference.' });

      // Idempotent retry: an already-submitted review by this user returns its current state.
      const ref = adminDb.collection(REVIEWS).doc(reviewId);
      const pre = await ref.get();
      if (!pre.exists || pre.get('userUid') !== user.uid || pre.get('productId') !== productId || pre.get('orderId') !== orderId) {
        return res.status(404).json({ error: 'Review session not found. Please start again.' });
      }
      if (pre.get('status') !== 'draft') return res.json({ success: true, reviewId, status: pre.get('status'), duplicate: true });

      const rating = Number(body.rating);
      if (!Number.isInteger(rating) || rating < 1 || rating > 5) return res.status(400).json({ error: 'Please select a rating from 1 to 5 stars.' });
      const title = sanitizeText(body.title, REVIEW_CONFIG.titleMax);
      const reviewText = sanitizeText(body.reviewText, REVIEW_CONFIG.textMax);
      if (reviewText.length < REVIEW_CONFIG.textMin) return res.status(400).json({ error: `Review must be at least ${REVIEW_CONFIG.textMin} characters.` });

      // Re-verify eligibility and deadline at submission time.
      const elig = await computeEligibility(user, productId);
      const purchase = elig.purchases.find(p => p.orderId === orderId);
      if (!purchase) return res.status(403).json({ error: 'This purchase is not associated with your account.' });
      if (!purchase.eligible && purchase.reviewState !== 'draft') return res.status(403).json({ error: purchase.reason });
      if (!purchase.eligible) return res.status(403).json({ error: purchase.reason || 'This purchase is no longer eligible for review.' });

      const prefix = uploadPrefix(user.uid, productId, reviewId);
      const paths: string[] = Array.isArray(body.media) ? body.media.map((m: any) => String(m?.storagePath || m)) : [];
      if (new Set(paths).size !== paths.length) return res.status(400).json({ error: 'Duplicate media files.' });
      let media: any[];
      try {
        media = await Promise.all(paths.map(p => verifyMedia(p, prefix)));
      } catch (e: any) {
        return res.status(400).json({ error: e.message });
      }
      const images = media.filter(m => m.type === 'image').length, videos = media.length - images;
      if (images > REVIEW_CONFIG.maxImages || videos > REVIEW_CONFIG.maxVideos) {
        return res.status(400).json({ error: `Up to ${REVIEW_CONFIG.maxImages} photos and ${REVIEW_CONFIG.maxVideos} videos are allowed.` });
      }

      const customer = await findCustomerByAuthUser(user);
      const order = elig.orders.find((o: any) => String(o.id) === orderId);
      const purchaseDate = parseOrderDate(order?.createdAt || order?.orderDate || order?.date)!;
      const status = REVIEW_CONFIG.moderationEnabled ? 'pending' : 'published';

      const result = await adminDb.runTransaction(async tx => {
        const cur = await tx.get(ref);
        const aggRef = adminDb.collection(AGGREGATES).doc(productId);
        const aggSnap = await tx.get(aggRef);
        if (!cur.exists) throw Object.assign(new Error('Review session not found.'), { http: 404 });
        if (cur.get('status') !== 'draft') return { status: cur.get('status'), duplicate: true };
        tx.update(ref, {
          productId, userUid: user.uid, customerId: String(customer?.id || order?.customerId || user.uid),
          orderId, orderItemId: purchase.orderItemId, rating, title, reviewText,
          customerDisplayName: safeDisplayName(customer, user), verifiedPurchase: true,
          purchaseDate: Timestamp.fromDate(purchaseDate), status, media, mediaCount: media.length, hasMedia: media.length > 0,
          helpfulCount: 0, rankScore: computeRankScore(0, media.length, reviewText.length),
          createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
        if (status === 'published') aggregateDelta(tx, aggSnap, productId, null, { rating, mediaCount: media.length });
        return { status, duplicate: false };
      });

      // Remove any uploaded-but-unreferenced objects for this review.
      await deletePrefix(prefix, new Set(media.map(m => m.storagePath)));
      res.status(result.duplicate ? 200 : 201).json({ success: true, reviewId, ...result });
    } catch (err: any) {
      if (err?.http) return res.status(err.http).json({ error: err.message });
      console.error('[Reviews] submit failed:', err?.message);
      res.status(500).json({ error: 'Your review could not be saved. Please try again.' });
    }
  });

  // ─────────── Authenticated: helpful vote (one per user, not own review) ───────────
  app.post('/api/reviews/:reviewId/helpful', async (req, res) => {
    try {
      const user = await requireUser(req, res);
      if (!user) return;
      if (rateLimited(`helpful:${user.uid}`, 60, 3600000)) return res.status(429).json({ error: 'Too many requests.' });
      const reviewId = String(req.params.reviewId || '');
      if (!ID_RE.test(reviewId)) return res.status(400).json({ error: 'Invalid review.' });
      const ref = adminDb.collection(REVIEWS).doc(reviewId);
      const out = await adminDb.runTransaction(async tx => {
        const r = await tx.get(ref);
        const vote = await tx.get(ref.collection('helpful_votes').doc(user.uid));
        if (!r.exists || r.get('status') !== 'published') throw Object.assign(new Error('Review not found.'), { http: 404 });
        if (r.get('userUid') === user.uid) throw Object.assign(new Error('You cannot vote on your own review.'), { http: 403 });
        const count = Number(r.get('helpfulCount') || 0);
        if (vote.exists) return { helpfulCount: count, alreadyVoted: true };
        const next = count + 1;
        tx.create(vote.ref, { createdAt: FieldValue.serverTimestamp() });
        tx.update(ref, {
          helpfulCount: next,
          rankScore: computeRankScore(next, Number(r.get('mediaCount') || 0), String(r.get('reviewText') || '').length),
        });
        return { helpfulCount: next, alreadyVoted: false };
      });
      res.json(out);
    } catch (err: any) {
      if (err?.http) return res.status(err.http).json({ error: err.message });
      console.error('[Reviews] helpful failed:', err?.message);
      res.status(500).json({ error: 'Failed to record vote.' });
    }
  });

  // ─────────── Admin moderation & cleanup ───────────
  async function requireAdmin(req: any, res: any) {
    const user = await requireUser(req, res);
    if (!user) return null;
    const u = await adminDb.collection('users').doc(user.uid).get();
    if (!(user.admin === true || (u.exists && u.get('role') === 'Admin'))) {
      res.status(403).json({ error: 'Administrator access required.' });
      return null;
    }
    return user;
  }

  app.post('/api/admin/customer-reviews/:reviewId/status', async (req, res) => {
    try {
      const admin = await requireAdmin(req, res);
      if (!admin) return;
      const reviewId = String(req.params.reviewId || '');
      const next = String(req.body?.status || '');
      if (!ID_RE.test(reviewId) || !['published', 'rejected'].includes(next)) return res.status(400).json({ error: 'Invalid request.' });
      const ref = adminDb.collection(REVIEWS).doc(reviewId);
      const out = await adminDb.runTransaction(async tx => {
        const r = await tx.get(ref);
        if (!r.exists || r.get('status') === 'draft') throw Object.assign(new Error('Review not found.'), { http: 404 });
        const aggSnap = await tx.get(adminDb.collection(AGGREGATES).doc(r.get('productId')));
        const prev = r.get('status');
        if (prev === next) return { status: next };
        const shape = { rating: Number(r.get('rating')), mediaCount: Number(r.get('mediaCount') || 0) };
        aggregateDelta(tx, aggSnap, r.get('productId'), prev === 'published' ? shape : null, next === 'published' ? shape : null);
        tx.update(ref, { status: next, moderatedAt: FieldValue.serverTimestamp(), moderatedBy: admin.uid, updatedAt: FieldValue.serverTimestamp() });
        return { status: next };
      });
      res.json({ success: true, reviewId, ...out });
    } catch (err: any) {
      if (err?.http) return res.status(err.http).json({ error: err.message });
      console.error('[Reviews] moderation failed:', err?.message);
      res.status(500).json({ error: 'Failed to update review.' });
    }
  });

  /** Removes stale drafts (>24h) and rejected reviews past retention, including their media. */
  app.post('/api/admin/customer-reviews/cleanup', async (req, res) => {
    try {
      const admin = await requireAdmin(req, res);
      if (!admin) return;
      const draftCut = Timestamp.fromMillis(Date.now() - REVIEW_CONFIG.draftTtlHours * 3600000);
      const rejCut = Timestamp.fromMillis(Date.now() - REVIEW_CONFIG.rejectedRetentionDays * 86400000);
      const [drafts, rejected] = await Promise.all([
        adminDb.collection(REVIEWS).where('status', '==', 'draft').where('createdAt', '<', draftCut).limit(200).get(),
        adminDb.collection(REVIEWS).where('status', '==', 'rejected').where('updatedAt', '<', rejCut).limit(200).get(),
      ]);
      const all = [...drafts.docs, ...rejected.docs];
      for (const d of all) {
        await deletePrefix(uploadPrefix(d.get('userUid'), d.get('productId'), d.id));
        await d.ref.delete();
      }
      res.json({ success: true, removedDrafts: drafts.size, removedRejected: rejected.size });
    } catch (err: any) {
      console.error('[Reviews] cleanup failed:', err?.message);
      res.status(500).json({ error: 'Cleanup failed.' });
    }
  });
}
