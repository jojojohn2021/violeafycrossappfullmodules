import { adminDb } from '../firebase-admin';

/**
 * Migration Helper: Sanitize mobile numbers by removing all whitespace.
 * e.g. "+91 9900040839" -> "+919900040839"
 */
function sanitizeMobileNumber(mobile: any): string {
  if (!mobile) return '';
  return String(mobile).replace(/\s+/g, '').trim();
}

/**
 * Migration Script: Remove blank spaces from `customerMobile` (and related mobile fields)
 * in the Firestore `sales_orders` collection.
 * 
 * Usage:
 *   npx ts-node scripts/sanitize_sales_orders_mobile.ts [--dry-run]
 */
async function sanitizeSalesOrdersMobile() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting sales_orders customerMobile Blank Space Removal... (Dry Run: ${isDryRun})`);

  try {
    const salesOrdersSnap = await adminDb.collection('sales_orders').get();
    console.log(`[Migration] Found ${salesOrdersSnap.size} sales_order document(s) in total.`);

    let scannedCount = 0;
    let modifiedCount = 0;
    const batchSize = 400;
    let batch = adminDb.batch();
    let batchOperationCount = 0;

    for (const doc of salesOrdersSnap.docs) {
      scannedCount++;
      const data = doc.data();

      const rawMobile = data.customerMobile || data.contactNo || data.phone || data.mobile || data.orderPayload?.customerMobile || '';
      const sanitizedCustomerMobile = sanitizeMobileNumber(rawMobile);

      const updates: Record<string, any> = {};

      if (data.customerMobile !== sanitizedCustomerMobile) {
        updates['customerMobile'] = sanitizedCustomerMobile;
      }

      if (data.contactNo && data.contactNo !== sanitizeMobileNumber(data.contactNo)) {
        updates['contactNo'] = sanitizeMobileNumber(data.contactNo);
      }

      if (data.phone && data.phone !== sanitizeMobileNumber(data.phone)) {
        updates['phone'] = sanitizeMobileNumber(data.phone);
      }

      if (data.mobile && data.mobile !== sanitizeMobileNumber(data.mobile)) {
        updates['mobile'] = sanitizeMobileNumber(data.mobile);
      }

      if (Object.keys(updates).length > 0) {
        modifiedCount++;
        console.log(`[Migration] Doc ${doc.id} (Order #${data.orderNumber || doc.id}): ` +
          `customerMobile "${data.customerMobile}" -> "${sanitizedCustomerMobile}"`);

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
    }

    if (!isDryRun && batchOperationCount > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOperationCount} updates.`);
    }

    console.log('\n[Migration Summary]');
    console.log(`Total Sales Order Records Scanned : ${scannedCount}`);
    console.log(`Records Modified / Sanitized    : ${modifiedCount}`);
    console.log(`Dry Run Mode                     : ${isDryRun}`);
    console.log('[Migration] Finished successfully.');
  } catch (err: any) {
    console.error('[Migration Error]', err);
    process.exit(1);
  }
}

sanitizeSalesOrdersMobile();
