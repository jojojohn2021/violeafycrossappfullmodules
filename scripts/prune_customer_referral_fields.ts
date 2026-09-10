import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '../firebase-admin.js';

/**
 * Migration Script: Prune Redundant CamelCase Referral Fields from `customers` collection.
 * 
 * Usage:
 *   npx ts-node scripts/prune_customer_referral_fields.ts [--dry-run]
 */
async function pruneCustomerReferralFields() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting Customer Referral Fields Pruning... (Dry Run: ${isDryRun})`);

  try {
    const customersSnap = await adminDb.collection('customers').get();
    console.log(`[Migration] Found ${customersSnap.size} customer document(s) in total.`);

    let scannedCount = 0;
    let modifiedCount = 0;
    const batchSize = 400;
    let batch = adminDb.batch();
    let batchOperationCount = 0;

    for (const doc of customersSnap.docs) {
      scannedCount++;
      const data = doc.data();
      const hasCamelCaseCode = Object.prototype.hasOwnProperty.call(data, 'referralCode');
      const hasCamelCasePartner = Object.prototype.hasOwnProperty.call(data, 'referralPartner');

      if (!hasCamelCaseCode && !hasCamelCasePartner) {
        continue;
      }

      const updates: Record<string, any> = {};

      // 1. Backfill lowercase fields if missing/empty but camelCase fields exist
      if ((!data.referralcode || String(data.referralcode).trim().length === 0) && data.referralCode) {
        updates['referralcode'] = data.referralCode;
      }
      if ((!data.referralpartner || String(data.referralpartner).trim().length === 0) && data.referralPartner) {
        updates['referralpartner'] = data.referralPartner;
      }

      // 2. Mark camelCase fields for deletion
      if (hasCamelCaseCode) {
        updates['referralCode'] = FieldValue.delete();
      }
      if (hasCamelCasePartner) {
        updates['referralPartner'] = FieldValue.delete();
      }

      modifiedCount++;
      console.log(`[Migration] Pruning doc: ${doc.id} (Name: "${data.name || 'N/A'}")`);

      if (!isDryRun) {
        batch.update(doc.ref, updates);
        batchOperationCount++;

        if (batchOperationCount >= batchSize) {
          await batch.commit();
          console.log(`[Migration] Committed batch of ${batchOperationCount} updates.`);
          batch = adminDb.batch();
          batchOperationCount = 0;
        }
      }
    }

    if (!isDryRun && batchOperationCount > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOperationCount} updates.`);
    }

    console.log('\n[Migration Summary]');
    console.log(`Total Customer Records Scanned : ${scannedCount}`);
    console.log(`Records Modified / Pruned       : ${modifiedCount}`);
    console.log(`Dry Run Mode                  : ${isDryRun}`);
    console.log('[Migration] Finished successfully.');
  } catch (err: any) {
    console.error('[Migration Error]', err);
    process.exit(1);
  }
}

pruneCustomerReferralFields();
