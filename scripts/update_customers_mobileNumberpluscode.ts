import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '../firebase-admin';

/**
 * Helper to compute `mobileNumberpluscode` by combining mobileCountrycode + mobileNumber
 * and stripping ALL whitespace/blank spaces.
 */
export function formatMobileNumberPlusCode(mobileCountrycode?: string, mobileNumber?: string): string {
  const cleanCountryCode = String(mobileCountrycode || '').replace(/\s+/g, '').trim();
  const cleanMobile = String(mobileNumber || '').replace(/\s+/g, '').trim();

  const digitsOnly = cleanMobile.replace(/\D/g, '');
  if (!digitsOnly) {
    return '';
  }

  let countryCode = cleanCountryCode;
  if (!countryCode) {
    countryCode = '+91';
  } else if (!countryCode.startsWith('+') && /^\d+$/.test(countryCode)) {
    countryCode = '+' + countryCode;
  }

  if (cleanMobile.startsWith('+')) {
    return cleanMobile.replace(/\s+/g, '');
  }

  const ccDigits = countryCode.replace(/\D/g, '');
  if (ccDigits && digitsOnly.startsWith(ccDigits) && digitsOnly.length > 10) {
    return '+' + digitsOnly;
  }

  return `${countryCode}${digitsOnly}`.replace(/\s+/g, '');
}

/**
 * Migration Script: Add and update `mobileNumberpluscode` field for all customer documents in Firestore.
 * Formula: `mobileCountrycode` + `mobileNumber` with all blank space removed.
 * Also builds unique index records in `customer_mobile_plus_code_index` to enforce no duplicates.
 * 
 * Usage:
 *   npx tsx scripts/update_customers_mobileNumberpluscode.ts [--dry-run]
 */
async function updateCustomersMobileNumberPlusCode() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting mobileNumberpluscode backfill & indexing for customers... (Dry Run: ${isDryRun})`);

  try {
    const customersSnap = await adminDb.collection('customers').get();
    console.log(`[Migration] Found ${customersSnap.size} customer document(s) in total.`);

    let scannedCount = 0;
    let modifiedCount = 0;
    let duplicateCount = 0;
    const batchSize = 250;
    let batch = adminDb.batch();
    let batchOperationCount = 0;

    const seenPlusCodes = new Map<string, string>(); // mobileNumberpluscode -> docId

    for (const doc of customersSnap.docs) {
      scannedCount++;
      const data = doc.data();

      const countryCode = data.mobileCountrycode || data.mobileCountryCode || data.countrymobilecode || data.countryMobileCode || '+91';
      const rawMobile = data.mobileNumber || data.mobile || data.phone || '';

      const computedPlusCode = formatMobileNumberPlusCode(countryCode, rawMobile);

      // Duplicate check (only if plusCode is non-empty)
      if (computedPlusCode) {
        if (seenPlusCodes.has(computedPlusCode)) {
          duplicateCount++;
          console.warn(`[Migration Warning] Duplicate mobileNumberpluscode detected: "${computedPlusCode}" ` +
            `for doc "${doc.id}" (already seen in doc "${seenPlusCodes.get(computedPlusCode)}")`);
        } else {
          seenPlusCodes.set(computedPlusCode, doc.id);
        }
      }

      const currentPlusCode = data.mobileNumberpluscode;
      const currentCountryCode = data.mobileCountrycode;

      const needsUpdate = currentPlusCode !== computedPlusCode || !currentCountryCode;

      if (needsUpdate) {
        modifiedCount++;
        console.log(`[Migration] Updating doc ${doc.id} (${data.name || 'N/A'}): ` +
          `mobileCountrycode="${countryCode}", mobileNumberpluscode="${computedPlusCode}"`);

        if (!isDryRun) {
          const updates: Record<string, any> = {
            mobileNumberpluscode: computedPlusCode,
            mobileCountrycode: countryCode,
            updatedAt: new Date().toISOString()
          };
          batch.update(doc.ref, updates);
          batchOperationCount++;

          // Also set unique index document in customer_mobile_plus_code_index if non-empty
          if (computedPlusCode) {
            const indexRef = adminDb.collection('customer_mobile_plus_code_index').doc(computedPlusCode);
            batch.set(indexRef, {
              customerId: doc.id,
              mobileNumberpluscode: computedPlusCode,
              updatedAt: new Date().toISOString()
            }, { merge: true });
            batchOperationCount++;
          }

          if (batchOperationCount >= batchSize) {
            await batch.commit();
            console.log(`[Migration] Committed batch of ${batchOperationCount} operations.`);
            batch = adminDb.batch();
            batchOperationCount = 0;
          }
        }
      } else {
        // Even if customer doc is up-to-date, ensure index document exists if non-empty
        if (!isDryRun && computedPlusCode) {
          const indexRef = adminDb.collection('customer_mobile_plus_code_index').doc(computedPlusCode);
          batch.set(indexRef, {
            customerId: doc.id,
            mobileNumberpluscode: computedPlusCode,
            updatedAt: new Date().toISOString()
          }, { merge: true });
          batchOperationCount++;

          if (batchOperationCount >= batchSize) {
            await batch.commit();
            console.log(`[Migration] Committed batch of ${batchOperationCount} operations.`);
            batch = adminDb.batch();
            batchOperationCount = 0;
          }
        }
      }
    }

    if (!isDryRun && batchOperationCount > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOperationCount} operations.`);
    }

    console.log('\n[Migration Summary]');
    console.log(`Total Customer Records Scanned : ${scannedCount}`);
    console.log(`Records Modified / Backfilled : ${modifiedCount}`);
    console.log(`Duplicate PlusCodes Flagged   : ${duplicateCount}`);
    console.log(`Dry Run Mode                  : ${isDryRun}`);
    console.log('[Migration] Finished successfully.');
  } catch (err: any) {
    console.error('[Migration Error]', err);
    process.exit(1);
  }
}

updateCustomersMobileNumberPlusCode();
