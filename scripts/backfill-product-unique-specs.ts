import { adminDb } from '../firebase-admin.js';

/**
 * One-Time Backfill: add uniqueSpec1..uniqueSpec4 to every `products` document.
 *
 * - Only fields that are MISSING are added, with value null (= "empty" in the app).
 * - Existing uniqueSpec values are never overwritten; no other fields are touched.
 * - Existing values longer than 30 characters are reported (not modified).
 *
 * Usage:
 *   Dry-Run: npx tsx scripts/backfill-product-unique-specs.ts --dry-run
 *   Live:    npx tsx scripts/backfill-product-unique-specs.ts
 */
const SPEC_FIELDS = ['uniqueSpec1', 'uniqueSpec2', 'uniqueSpec3', 'uniqueSpec4'] as const;
const MAX_LEN = 30;
const BATCH_LIMIT = 400;

async function backfillUniqueSpecs() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`Product uniqueSpec backfill — ${isDryRun ? 'DRY-RUN (no writes)' : 'LIVE'}`);

  const snap = await adminDb.collection('products').get();
  let toUpdate = 0;
  let alreadyComplete = 0;
  let written = 0;
  const overLength: string[] = [];

  let batch = adminDb.batch();
  let batchOps = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const patch: Record<string, null> = {};

    for (const f of SPEC_FIELDS) {
      if (!(f in data)) {
        patch[f] = null;
      } else if (typeof data[f] === 'string' && data[f].trim().length > MAX_LEN) {
        overLength.push(`${doc.id}.${f} (${data[f].trim().length} chars)`);
      }
    }

    if (Object.keys(patch).length === 0) {
      alreadyComplete++;
      continue;
    }

    toUpdate++;
    if (isDryRun) {
      console.log(`  would update ${doc.id}: ${Object.keys(patch).join(', ')}`);
      continue;
    }

    batch.update(doc.ref, patch);
    batchOps++;
    if (batchOps >= BATCH_LIMIT) {
      await batch.commit();
      written += batchOps;
      batch = adminDb.batch();
      batchOps = 0;
    }
  }

  if (!isDryRun && batchOps > 0) {
    await batch.commit();
    written += batchOps;
  }

  console.log('----------------------------------------');
  console.log(`Scanned:           ${snap.size}`);
  console.log(`Already complete:  ${alreadyComplete}`);
  console.log(`${isDryRun ? 'Would update' : 'Updated'}:      ${isDryRun ? toUpdate : written}`);
  if (overLength.length) {
    console.log(`Existing values over ${MAX_LEN} chars (not modified):`);
    overLength.forEach((s) => console.log(`  - ${s}`));
  }
}

backfillUniqueSpecs()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
