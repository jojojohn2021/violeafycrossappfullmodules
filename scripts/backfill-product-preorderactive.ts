import { adminDb } from '../firebase-admin.js';

/**
 * One-Time Backfill: add `preorderactive: false` (boolean) to every `products` document.
 *
 * - Any product document missing `preorderactive` (or where `preorderactive` is not a boolean)
 *   is updated with `{ preorderactive: false }`.
 * - Existing boolean `preorderactive` values are preserved; no other fields are modified.
 *
 * Usage:
 *   Dry-Run: npx tsx scripts/backfill-product-preorderactive.ts --dry-run
 *   Live:    npx tsx scripts/backfill-product-preorderactive.ts
 */
const FIELD_NAME = 'preorderactive';
const DEFAULT_VALUE = false;
const BATCH_LIMIT = 400;

async function backfillProductPreorderActive() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`Product ${FIELD_NAME} backfill — ${isDryRun ? 'DRY-RUN (no writes)' : 'LIVE'}`);

  const snap = await adminDb.collection('products').get();
  let toUpdate = 0;
  let alreadySet = 0;
  let written = 0;

  let batch = adminDb.batch();
  let batchOps = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};

    if (typeof data[FIELD_NAME] === 'boolean') {
      alreadySet++;
      continue;
    }

    toUpdate++;
    if (isDryRun) {
      console.log(`  would update ${doc.id} (${data.name || 'unnamed'}): ${FIELD_NAME} = ${DEFAULT_VALUE}`);
      continue;
    }

    batch.update(doc.ref, { [FIELD_NAME]: DEFAULT_VALUE });
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

  // Verification pass
  const verifySnap = await adminDb.collection('products').get();
  let verifiedCount = 0;
  let missingCount = 0;
  for (const doc of verifySnap.docs) {
    const data = doc.data() || {};
    if (typeof data[FIELD_NAME] === 'boolean') {
      verifiedCount++;
    } else {
      missingCount++;
    }
  }

  console.log('----------------------------------------');
  console.log(`Scanned:            ${snap.size}`);
  console.log(`Already had field:  ${alreadySet}`);
  console.log(`${isDryRun ? 'Would update' : 'Updated'}:       ${isDryRun ? toUpdate : written}`);
  console.log(`Verified with bool: ${verifiedCount}/${verifySnap.size} (missing: ${missingCount})`);
}

backfillProductPreorderActive()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
