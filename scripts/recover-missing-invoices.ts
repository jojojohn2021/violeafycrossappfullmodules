import { adminDb } from '../firebase-admin.js';
import { ensureInvoiceForOrder } from '../server.js';

interface RecoveryFailure {
  orderId: string;
  invoiceId?: string;
  error: string;
}

/**
 * One-Time Missing Invoice Recovery Script
 * 
 * Scans existing `sales_orders` in Firestore and automatically creates missing
 * invoice documents in the `invoices` collection by reusing `ensureInvoiceForOrder(order)`.
 * 
 * Usage:
 *   Dry-Run: npm run recover:invoices -- --dry-run
 *   Live:    npm run recover:invoices
 */
async function recoverMissingInvoices() {
  const isDryRun = process.argv.includes('--dry-run');
  const startTime = new Date().toISOString();

  console.log(`========================================`);
  console.log(`VioLeafyCross Invoice Recovery`);
  console.log(`Start Time: ${startTime}`);
  console.log(`Dry-Run Mode: ${isDryRun ? 'YES (No writes will be performed)' : 'NO (Live Execution)'}`);
  console.log(`========================================\n`);

  let scannedCount = 0;
  let skippedCount = 0;
  let createdCount = 0;
  let failedCount = 0;
  const failures: RecoveryFailure[] = [];

  try {
    const salesOrdersSnap = await adminDb.collection('sales_orders').get();
    const invoicesSnap = await adminDb.collection('invoices').get();

    const existingInvoicesByOrderId = new Set<string>();
    const existingInvoicesById = new Set<string>();

    invoicesSnap.docs.forEach((doc) => {
      const data = doc.data();
      if (data.orderId) existingInvoicesByOrderId.add(String(data.orderId));
      if (data.invoiceId) existingInvoicesById.add(String(data.invoiceId));
      existingInvoicesById.add(String(doc.id));
    });

    console.log(`[Scan] Found ${salesOrdersSnap.size} Sales Order(s) and ${invoicesSnap.size} existing Invoice(s) in Firestore.\n`);

    for (const doc of salesOrdersSnap.docs) {
      scannedCount++;
      const order = { id: doc.id, ...doc.data() };
      const orderId = order.id;
      const existingInvoiceId = order.invoiceId;

      const invoiceExists =
        existingInvoicesByOrderId.has(orderId) ||
        (existingInvoiceId && existingInvoicesById.has(existingInvoiceId));

      if (invoiceExists) {
        skippedCount++;
        continue;
      }

      console.log(`[Missing Invoice Detected] Sales Order ID: ${orderId} (Order #: ${order.orderNumber || 'N/A'})`);

      if (isDryRun) {
        createdCount++;
        console.log(`  -> [DRY RUN] Would generate invoice for Order ID: ${orderId}`);
        continue;
      }

      try {
        const result = await ensureInvoiceForOrder(order);
        
        // Verify document creation in Firestore
        const verifySnap = await adminDb.collection('invoices').doc(result.invoiceId).get();
        if (verifySnap.exists) {
          createdCount++;
          console.log(`  -> SUCCESS: Generated & Verified Invoice ${result.invoiceId} for Order ${orderId}`);
        } else {
          failedCount++;
          const err = `Verification failed: Invoice document ${result.invoiceId} not found in Firestore after creation.`;
          console.error(`  -> FAILED: ${err}`);
          failures.push({ orderId, invoiceId: result.invoiceId, error: err });
        }
      } catch (err: any) {
        failedCount++;
        const errMsg = err.message || String(err);
        console.error(`  -> FAILED for Order ${orderId}: ${errMsg}`);
        failures.push({ orderId, error: errMsg });
      }
    }

    const endTime = new Date().toISOString();

    console.log(`\n========================================`);
    console.log(`VioLeafyCross Invoice Recovery Summary`);
    console.log(`========================================`);
    console.log(`START TIME             : ${startTime}`);
    console.log(`END TIME               : ${endTime}`);
    console.log(`Dry Run Mode           : ${isDryRun ? 'YES' : 'NO'}`);
    console.log(`Sales Orders Scanned   : ${scannedCount}`);
    console.log(`Invoices Already Exist : ${skippedCount}`);
    console.log(`Invoices Created       : ${createdCount}`);
    console.log(`Failed                 : ${failedCount}`);
    console.log(`========================================\n`);

    if (failures.length > 0) {
      console.log(`Failed Invoice Recovery Details (${failures.length}):\n`);
      failures.forEach((f, idx) => {
        console.log(`${idx + 1}. Sales Order: ${f.orderId}`);
        if (f.invoiceId) console.log(`   Invoice ID: ${f.invoiceId}`);
        console.log(`   Error: ${f.error}\n`);
      });
    }

    if (failedCount > 0) {
      process.exitCode = 1;
    }
  } catch (err: any) {
    console.error(`\n[Fatal Error] Invoice recovery process encountered an unhandled exception:`, err);
    process.exit(1);
  }
}

recoverMissingInvoices();
