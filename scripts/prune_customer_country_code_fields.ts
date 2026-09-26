import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '../firebase-admin';

/**
 * Migration Script: Prune duplicate mobile country code fields from `customers` collection in Firestore.
 * Standard field to keep: `countrymobilecode`
 * Fields to prune: `mobileCountryCode`, `countryMobileCode`, `mobilecountrycode`
 * 
 * Usage:
 *   npx tsx scripts/prune_customer_country_code_fields.ts [--dry-run]
 */
async function pruneCustomerCountryCodeFields() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting Customer Country Code Fields Pruning... (Dry Run: ${isDryRun})`);

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

      // Check for duplicate field variations
      const hasCountryMobileCodeCamel = Object.prototype.hasOwnProperty.call(data, 'countryMobileCode');
      const hasMobileCountryCodeCamel = Object.prototype.hasOwnProperty.call(data, 'mobileCountryCode');
      const hasMobileCountryCodeLower = Object.prototype.hasOwnProperty.call(data, 'mobilecountrycode');
      const hasStandardField = Object.prototype.hasOwnProperty.call(data, 'countrymobilecode');

      // Detect any duplicate / non-standard country code fields
      const hasDuplicates = hasCountryMobileCodeCamel || hasMobileCountryCodeCamel || hasMobileCountryCodeLower;

      if (!hasDuplicates) {
        continue;
      }

      const updates: Record<string, any> = {};

      // 1. Backfill standard `countrymobilecode` if missing or empty, using value from alternate fields
      const existingVal = data.countrymobilecode || data.countryMobileCode || data.mobileCountryCode || data.mobilecountrycode || '+91';
      if (!hasStandardField || !data.countrymobilecode || String(data.countrymobilecode).trim().length === 0) {
        updates['countrymobilecode'] = existingVal;
      }

      // 2. Mark duplicate/alternate fields for deletion
      if (hasCountryMobileCodeCamel) {
        updates['countryMobileCode'] = FieldValue.delete();
      }
      if (hasMobileCountryCodeCamel) {
        updates['mobileCountryCode'] = FieldValue.delete();
      }
      if (hasMobileCountryCodeLower) {
        updates['mobilecountrycode'] = FieldValue.delete();
      }

      modifiedCount++;
      console.log(`[Migration] Pruning doc: ${doc.id} (Name: "${data.name || 'N/A'}") | ` +
        `Existing fields: countrymobilecode="${data.countrymobilecode}", ` +
        `countryMobileCode="${data.countryMobileCode}", ` +
        `mobileCountryCode="${data.mobileCountryCode}", ` +
        `mobilecountrycode="${data.mobilecountrycode}"`);

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

pruneCustomerCountryCodeFields();
