// Run: npx tsx --test test/server/customerReviews.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  computeReviewDeadline, orderLifecycleState, findProductLines, sanitizeText, buildSummary,
  sniffMime, mimeCompatible, safeDisplayName, computeRankScore, parseOrderDate,
} from '../../src/reviews/customerReviews';

const IST = 330 * 60000;

test('deadline is end of the 60th IST calendar day', () => {
  // 1 Jan 2026 10:00 IST
  const purchase = new Date(Date.UTC(2026, 0, 1, 10, 0) - IST);
  const d = computeReviewDeadline(purchase);
  // 1 Jan + 60 days = 2 Mar 2026, 23:59:59.999 IST
  assert.equal(d.getTime(), Date.UTC(2026, 2, 2, 23, 59, 59, 999) - IST);
});

test('deadline boundary: late-night IST purchase uses IST date, not UTC date', () => {
  // 1 Jan 2026 00:30 IST == 31 Dec 2025 19:00 UTC
  const purchase = new Date(Date.UTC(2026, 0, 1, 0, 30) - IST);
  const d = computeReviewDeadline(purchase);
  assert.equal(d.getTime(), Date.UTC(2026, 2, 2, 23, 59, 59, 999) - IST);
  const lastMs = new Date(d.getTime());
  const afterMs = new Date(d.getTime() + 1);
  assert.ok(lastMs.getTime() <= d.getTime());
  assert.ok(afterMs.getTime() > d.getTime());
});

test('order lifecycle qualification', () => {
  assert.equal(orderLifecycleState({ orderStatus: 'Confirmed', deliveryStatus: 'Delivered' }).qualifies, true);
  assert.equal(orderLifecycleState({ orderStatus: 'Completed' }).qualifies, true);
  assert.equal(orderLifecycleState({ orderStatus: 'Confirmed', deliveryStatus: 'Processing' }).qualifies, false);
  assert.equal(orderLifecycleState({ orderStatus: 'Cancelled', deliveryStatus: 'Delivered' }).qualifies, false);
  assert.equal(orderLifecycleState({ deliveryStatus: 'Returned' }).qualifies, false);
});

test('findProductLines matches exact product IDs in multi-product orders', () => {
  const order = { products: [{ productId: 'A1' }, { id: 'B2' }, { productId: 'A10' }] };
  assert.deepEqual(findProductLines(order, 'A1').map(l => l.orderItemId), ['line-0']);
  assert.equal(findProductLines(order, 'B2').length, 1);
  assert.equal(findProductLines(order, 'Z').length, 0);
  assert.equal(findProductLines({ orderPayload: { products: [{ productId: 'X' }] } }, 'X').length, 1);
});

test('summary handles zero reviews and percentages', () => {
  const empty = buildSummary(null);
  assert.equal(empty.averageRating, 0);
  assert.equal(empty.totalRatings, 0);
  assert.ok(empty.breakdown.every(b => b.percent === 0));
  const s = buildSummary({ ratingCount: 4, ratingSum: 17, distribution: { '5': 2, '4': 1, '3': 1 } });
  assert.equal(s.averageRating, 4.3);
  assert.deepEqual(s.breakdown.map(b => b.percent), [50, 25, 25, 0, 0]);
});

test('sanitizeText strips markup and control chars', () => {
  assert.equal(sanitizeText('<b>Great</b>\u0007 product<script>x</script>', 100), 'Great productx');
  assert.equal(sanitizeText('a'.repeat(200), 120).length, 120);
});

test('MIME sniffing rejects disguised files', () => {
  const jpg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom')]);
  const heic = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypheic')]);
  assert.equal(sniffMime(jpg), 'image/jpeg');
  assert.equal(sniffMime(mp4), 'video/mp4');
  assert.equal(sniffMime(heic), 'image/heic');
  assert.ok(mimeCompatible('video/quicktime', 'video/mp4'));
  assert.ok(!mimeCompatible('image/png', 'image/jpeg'));
  assert.ok(!mimeCompatible('image/jpeg', sniffMime(Buffer.from('%PDF-1.7 hello'))));
});

test('display name never exposes phone/email', () => {
  assert.equal(safeDisplayName({ name: 'Ravi Kumar' }, {}), 'Ravi K.');
  assert.equal(safeDisplayName({ name: '+919876543210' }, {}), 'VioLeafy Customer');
  assert.equal(safeDisplayName({ name: 'a@b.com' }, {}), 'VioLeafy Customer');
});

test('rank score ignores rating, rewards helpfulness first', () => {
  assert.ok(computeRankScore(1, 0, 0) > computeRankScore(0, 3, 1000));
});

test('parseOrderDate supports existing formats', () => {
  assert.ok(parseOrderDate('2026-01-01T00:00:00.000Z'));
  assert.ok(parseOrderDate({ _seconds: 1767225600 }));
  assert.equal(parseOrderDate('bad'), null);
});
