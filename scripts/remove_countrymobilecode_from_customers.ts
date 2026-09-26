import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '../firebase-admin';

/**
 * Migration Script: Remove `countrymobilecode` field from all documents in `customers` collection in Firestore.
 * 
 * Usage:
 *   npx tsx scripts/remove_countrymobilecode_from_customers.ts [--dry-run]
 */
async function removeCountryMobileCodeFromCustomers() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting Removal of countrymobilecode from customers collection... (Dry Run: ${isDryRun})`);

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

      const hasCountryMobileCode = Object.prototype.hasOwnProperty.call(data, 'countrymobilecode') ||
                                   Object.prototype.hasOwnProperty.call(data, 'countryMobileCode') ||
                                   Object.prototype.hasOwnProperty.call(data, 'mobileCountryCode') ||
                                   Object.prototype.hasOwnProperty.call(data, 'mobilecountrycode');

      if (!hasCountryMobileCode) {
        continue;
      }

      const updates: Record<string, any> = {};

      if (Object.prototype.hasOwnProperty.call(data, 'countrymobilecode')) {
        updates['countrymobilecode'] = FieldValue.delete();
      }
      if (Object.prototype.hasOwnProperty.call(data, 'countryMobileCode')) {
        updates['countryMobileCode'] = FieldValue.delete();
      }
      if (Object.prototype.hasOwnProperty.call(data, 'mobileCountryCode')) {
        updates['mobileCountryCode'] = FieldValue.delete();
      }
      if (Object.prototype.hasOwnProperty.call(data, 'mobilecountrycode')) {
        updates['mobilecountrycode'] = FieldValue.delete();
      }

      modifiedCount++;
      console.log(`[Migration] Deleting countrymobilecode from doc: ${doc.id} (Name: "${data.name || 'N/A'}")`);

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

removeCountryMobileCodeFromCustomers();
