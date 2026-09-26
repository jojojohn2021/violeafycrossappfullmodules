import { adminDb } from '../firebase-admin';
import { formatMobileNumberPlusCode } from './update_customers_mobileNumberpluscode';

function sanitizeMobile(mobile: any): string {
  if (!mobile) return '';
  return String(mobile).replace(/\s+/g, '').trim();
}

function get10DigitMobile(mobile: any): string {
  const digits = String(mobile || '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : digits;
}

/**
 * Migration Script: Link sales_orders, commission_transactions, and payments
 * to customers table:
 * - customerMobile linked to customer's mobileNumberpluscode
 * - customerId linked to customer document id
 * 
 * Usage:
 *   npx tsx scripts/link_sales_orders_and_transactions.ts [--dry-run]
 */
async function linkSalesOrdersAndTransactions() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Migration] Starting linking of sales_orders & transactions to customer.id & mobileNumberpluscode... (Dry Run: ${isDryRun})`);

  try {
    // Load all customers into memory for fast lookup
    const customersSnap = await adminDb.collection('customers').get();
    console.log(`[Migration] Loaded ${customersSnap.size} customer document(s).`);

    const customerByDocId = new Map<string, any>();
    const customerByAuthUid = new Map<string, any>();
    const customerByPlusCode = new Map<string, any>();
    const customerBy10DigitMobile = new Map<string, any>();

    for (const doc of customersSnap.docs) {
      const data = { id: doc.id, ...doc.data() };
      customerByDocId.set(doc.id, data);
      if (data.customerId) {
        customerByDocId.set(data.customerId, data);
      }
      if (data.authUid) {
        customerByAuthUid.set(data.authUid, data);
      }

      const countryCode = data.mobileCountrycode || data.mobileCountryCode || data.countrymobilecode || data.countryMobileCode || '+91';
      const rawMobile = data.mobileNumber || data.mobile || data.phone || '';
      const plusCode = data.mobileNumberpluscode || formatMobileNumberPlusCode(countryCode, rawMobile);

      if (plusCode) {
        customerByPlusCode.set(plusCode, data);
      }
      const m10 = get10DigitMobile(rawMobile);
      if (m10) {
        customerBy10DigitMobile.set(m10, data);
      }
    }

    function findCustomer(idOrAuth?: string, rawMobile?: string): any | null {
      const cleanId = String(idOrAuth || '').trim();
      if (cleanId && cleanId !== 'guest' && cleanId !== 'anonymous' && cleanId !== 'organic') {
        if (customerByDocId.has(cleanId)) return customerByDocId.get(cleanId);
        if (customerByAuthUid.has(cleanId)) return customerByAuthUid.get(cleanId);
      }

      const sanitizedMob = sanitizeMobile(rawMobile);
      if (sanitizedMob && customerByPlusCode.has(sanitizedMob)) {
        return customerByPlusCode.get(sanitizedMob);
      }

      const m10 = get10DigitMobile(rawMobile);
      if (m10) {
        const plus1 = `+91${m10}`;
        if (customerByPlusCode.has(plus1)) return customerByPlusCode.get(plus1);
        if (customerBy10DigitMobile.has(m10)) return customerBy10DigitMobile.get(m10);
      }

      return null;
    }

    // 1. Process sales_orders
    const ordersSnap = await adminDb.collection('sales_orders').get();
    console.log(`[Migration] Found ${ordersSnap.size} sales_order document(s).`);

    let ordersModified = 0;
    let batch = adminDb.batch();
    let batchOps = 0;
    const batchSize = 250;

    for (const doc of ordersSnap.docs) {
      const data = doc.data();
      const rawMobile = data.customerMobile || data.contactNo || data.phone || data.mobile || data.orderPayload?.customerMobile || data.orderPayload?.phone || '';
      const rawId = data.customerId || data.userId || data.orderPayload?.customerId || '';

      const matchedCust = findCustomer(rawId, rawMobile);
      if (matchedCust) {
        const targetCustomerId = matchedCust.id; // Customer Document ID
        const targetPlusCode = matchedCust.mobileNumberpluscode || formatMobileNumberPlusCode(matchedCust.mobileCountrycode, matchedCust.mobileNumber);

        const currentCustId = data.customerId;
        const currentMobile = data.customerMobile;

        if (currentCustId !== targetCustomerId || currentMobile !== targetPlusCode) {
          ordersModified++;
          console.log(`[Migration] Updating sales_order ${doc.id} (Order #${data.orderNumber || doc.id}): ` +
            `customerId="${currentCustId}" -> "${targetCustomerId}", customerMobile="${currentMobile}" -> "${targetPlusCode}"`);

          if (!isDryRun) {
            const updates: Record<string, any> = {
              customerId: targetCustomerId,
              customerMobile: targetPlusCode,
              updatedAt: new Date().toISOString()
            };
            if (data.orderPayload && typeof data.orderPayload === 'object') {
              updates['orderPayload.customerId'] = targetCustomerId;
              updates['orderPayload.customerMobile'] = targetPlusCode;
            }
            batch.update(doc.ref, updates);
            batchOps++;

            if (batchOps >= batchSize) {
              await batch.commit();
              console.log(`[Migration] Committed batch of ${batchOps} sales_order updates.`);
              batch = adminDb.batch();
              batchOps = 0;
            }
          }
        }
      }
    }

    if (!isDryRun && batchOps > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOps} sales_order updates.`);
      batch = adminDb.batch();
      batchOps = 0;
    }

    // 2. Process commission_transactions
    const commSnap = await adminDb.collection('commission_transactions').get();
    console.log(`[Migration] Found ${commSnap.size} commission_transaction document(s).`);

    let commModified = 0;
    for (const doc of commSnap.docs) {
      const data = doc.data();
      const rawMobile = data.customerMobile || data.customerPhone || data.phone || '';
      const rawId = data.customerId || data.userId || '';

      const matchedCust = findCustomer(rawId, rawMobile);
      if (matchedCust) {
        const targetCustomerId = matchedCust.id;
        const targetPlusCode = matchedCust.mobileNumberpluscode || formatMobileNumberPlusCode(matchedCust.mobileCountrycode, matchedCust.mobileNumber);

        if (data.customerId !== targetCustomerId || data.customerMobile !== targetPlusCode) {
          commModified++;
          console.log(`[Migration] Updating commission_transaction ${doc.id}: ` +
            `customerId="${data.customerId}" -> "${targetCustomerId}", customerMobile="${data.customerMobile}" -> "${targetPlusCode}"`);

          if (!isDryRun) {
            const updates: Record<string, any> = {
              customerId: targetCustomerId,
              customerMobile: targetPlusCode,
              updatedAt: new Date().toISOString()
            };
            batch.update(doc.ref, updates);
            batchOps++;

            if (batchOps >= batchSize) {
              await batch.commit();
              console.log(`[Migration] Committed batch of ${batchOps} commission_transaction updates.`);
              batch = adminDb.batch();
              batchOps = 0;
            }
          }
        }
      }
    }

    if (!isDryRun && batchOps > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOps} commission_transaction updates.`);
      batch = adminDb.batch();
      batchOps = 0;
    }

    // 3. Process payments
    const paySnap = await adminDb.collection('payments').get();
    console.log(`[Migration] Found ${paySnap.size} payment document(s).`);

    let payModified = 0;
    for (const doc of paySnap.docs) {
      const data = doc.data();
      const rawMobile = data.customerMobile || data.customerPhone || data.phone || data.orderPayload?.customerMobile || '';
      const rawId = data.customerId || data.userId || data.orderPayload?.customerId || '';

      const matchedCust = findCustomer(rawId, rawMobile);
      if (matchedCust) {
        const targetCustomerId = matchedCust.id;
        const targetPlusCode = matchedCust.mobileNumberpluscode || formatMobileNumberPlusCode(matchedCust.mobileCountrycode, matchedCust.mobileNumber);

        if (data.customerId !== targetCustomerId || data.customerMobile !== targetPlusCode) {
          payModified++;
          console.log(`[Migration] Updating payment ${doc.id}: ` +
            `customerId="${data.customerId}" -> "${targetCustomerId}", customerMobile="${data.customerMobile}" -> "${targetPlusCode}"`);

          if (!isDryRun) {
            const updates: Record<string, any> = {
              customerId: targetCustomerId,
              customerMobile: targetPlusCode,
              updatedAt: new Date().toISOString()
            };
            batch.update(doc.ref, updates);
            batchOps++;

            if (batchOps >= batchSize) {
              await batch.commit();
              console.log(`[Migration] Committed batch of ${batchOps} payment updates.`);
              batch = adminDb.batch();
              batchOps = 0;
            }
          }
        }
      }
    }

    if (!isDryRun && batchOps > 0) {
      await batch.commit();
      console.log(`[Migration] Committed final batch of ${batchOps} payment updates.`);
    }

    console.log('\n[Migration Summary]');
    console.log(`Sales Orders Updated             : ${ordersModified}`);
    console.log(`Commission Transactions Updated  : ${commModified}`);
    console.log(`Payments Updated                 : ${payModified}`);
    console.log(`Dry Run Mode                     : ${isDryRun}`);
    console.log('[Migration] Finished successfully.');
  } catch (err: any) {
    console.error('[Migration Error]', err);
    process.exit(1);
  }
}

linkSalesOrdersAndTransactions();
