import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '../firebase-admin.js';

const MAX_COMMISSION_LEVELS = 5;
const COMMISSION_RULES_DOC_ID = 'default_rules';

function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}

async function findCustomerByAuthUid(identifier: string): Promise<any | null> {
  if (!identifier) return null;
  const cleanId = identifier.trim();
  if (!cleanId) return null;

  // 1. Try customer document ID
  const directDoc = await adminDb.collection('customers').doc(cleanId).get();
  if (directDoc.exists) {
    return { id: directDoc.id, ...directDoc.data() };
  }

  // 2. Try authUid query
  const snapByAuth = await adminDb.collection('customers').where('authUid', '==', cleanId).limit(1).get();
  if (!snapByAuth.empty) {
    const doc = snapByAuth.docs[0];
    return { id: doc.id, ...doc.data() };
  }

  // 3. Try customerId field query
  const snapByCustId = await adminDb.collection('customers').where('customerId', '==', cleanId).limit(1).get();
  if (!snapByCustId.empty) {
    const doc = snapByCustId.docs[0];
    return { id: doc.id, ...doc.data() };
  }

  // 4. Try mobile index lookup
  const cleanMobile = cleanId.replaceAll(/\D/g, '');
  if (cleanMobile.length >= 10) {
    const mobileIndexDoc = await adminDb.collection('customer_mobile_index').doc(cleanMobile).get();
    if (mobileIndexDoc.exists) {
      const custId = mobileIndexDoc.data()?.customerId;
      if (custId) {
        const cDoc = await adminDb.collection('customers').doc(custId).get();
        if (cDoc.exists) {
          return { id: cDoc.id, ...cDoc.data() };
        }
      }
    }

    const snapByMobile = await adminDb.collection('customers').where('mobileNumber', '==', cleanMobile).limit(1).get();
    if (!snapByMobile.empty) {
      const doc = snapByMobile.docs[0];
      return { id: doc.id, ...doc.data() };
    }
  }

  return null;
}

async function resolveSponsorChain(buyerCustomer: any): Promise<Array<{ level: number; customer: any }>> {
  const chain: Array<{ level: number; customer: any }> = [];
  const visited = new Set<string>([buyerCustomer.authUid, buyerCustomer.id, buyerCustomer.mobileNumber].filter(Boolean));
  let sponsorIdentifier = buyerCustomer.referralcode || buyerCustomer.referralCode || buyerCustomer.sponsorAuthUid || buyerCustomer.sponsorId;

  // Organic customer: Treated as Level 1 self-sponsor for their own purchases
  if (!sponsorIdentifier || sponsorIdentifier === 'organic') {
    chain.push({ level: 1, customer: buyerCustomer });
    return chain;
  }

  for (let level = 1; level <= MAX_COMMISSION_LEVELS; level++) {
    if (!sponsorIdentifier || sponsorIdentifier === 'organic' || visited.has(sponsorIdentifier)) break;
    const sponsor = await findCustomerByAuthUid(sponsorIdentifier);
    if (!sponsor) break;
    chain.push({ level, customer: sponsor });
    visited.add(sponsorIdentifier);
    if (sponsor.authUid) visited.add(sponsor.authUid);
    if (sponsor.id) visited.add(sponsor.id);
    if (sponsor.mobileNumber) visited.add(sponsor.mobileNumber);
    sponsorIdentifier = sponsor.referralcode || sponsor.referralCode || sponsor.sponsorAuthUid || sponsor.sponsorId;
  }
  return chain;
}

function calculatePreGstCommissionBase(item: any): { base: number; gstExcluded: boolean; deliveryExcluded: boolean } {
  let base = 0;
  let gstExcluded = false;
  let deliveryExcluded = false;

  const totalTaxable = Number(item.totalTaxableValue || item.orderPayload?.totalTaxableValue || 0);
  if (totalTaxable > 0) {
    base = totalTaxable;
    gstExcluded = true;
    deliveryExcluded = true;
  } else {
    const products = item.products || item.orderPayload?.products;
    if (Array.isArray(products) && products.length > 0) {
      let productSum = 0;
      for (const p of products) {
        if (p.taxableValue && Number(p.taxableValue) > 0) {
          productSum += Number(p.taxableValue);
        } else if (p.price && p.quantity) {
          productSum += Number(p.price) * Number(p.quantity);
        }
      }
      if (productSum > 0) {
        base = productSum;
        gstExcluded = true;
        deliveryExcluded = true;
      }
    }
  }

  if (base <= 0) {
    const grandTotal = Number(item.totalValue || item.grandTotal || item.amount || item.orderPayload?.totalValue || 0);
    const gst = Number(item.totalGstAmount || item.gstAmount || item.orderPayload?.totalGstAmount || 0);
    const delivery = Number(item.deliveryFee || item.deliveryCharge || item.courierCharges || item.orderPayload?.deliveryFee || 0);
    
    if (gst > 0) gstExcluded = true;
    if (delivery > 0) deliveryExcluded = true;

    base = Math.max(0, grandTotal - gst - delivery);
  }

  return {
    base: roundCurrency(base),
    gstExcluded,
    deliveryExcluded,
  };
}

async function getEffectiveCommissionRate(level: number, productId?: string): Promise<number> {
  if (productId) {
    const overrideDoc = await adminDb.collection('product_level_commissions').doc(`${productId}_L${level}`).get();
    if (overrideDoc.exists && typeof overrideDoc.data()?.rate === 'number') {
      return overrideDoc.data()!.rate;
    }
  }
  const rulesDoc = await adminDb.collection('commission_rules').doc(COMMISSION_RULES_DOC_ID).get();
  if (rulesDoc.exists && rulesDoc.data()?.rates) {
    return Number(rulesDoc.data()!.rates[String(level)] ?? (level === 1 ? 5 : 0));
  }
  const defaultRates: Record<string, number> = { '1': 5, '2': 3, '3': 2, '4': 1, '5': 0.5 };
  return defaultRates[String(level)] ?? 0;
}

/**
 * Migration & Reprocessing Script:
 * Verifies all sales transactions in `violeafydb`, calculates pre-GST merchandise base commission for
 * organic self-sponsors (Level 1) and referred sponsor chains, writes commission_transactions, and
 * updates customer wallet pending balances.
 */
async function reprocessOrganicAndAllCommissions() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`[Reprocess Script] Starting All Transactions Commission Verification... (Dry Run: ${isDryRun})\n`);

  try {
    const salesOrdersSnap = await adminDb.collection('sales_orders').get();
    console.log(`[Reprocess Script] Found ${salesOrdersSnap.size} sales order document(s) in total.`);

    let totalEvaluated = 0;
    let newTransactionsCreated = 0;
    let existingTransactionsSkipped = 0;
    let customerWalletsUpdated = 0;
    let totalCommissionGenerated = 0;
    const walletIncrements: Record<string, number> = {};

    for (const doc of salesOrdersSnap.docs) {
      totalEvaluated++;
      const order = doc.data();
      const orderId = doc.id;
      const orderNum = order.orderNumber || orderId;

      const buyerIdentifier = order.customerId || order.userId || order.customerMobile || order.phone;
      if (!buyerIdentifier) {
        console.warn(`[Order ${orderNum}] Skipping: No customer identifier found.`);
        continue;
      }

      const buyerCustomer = await findCustomerByAuthUid(buyerIdentifier);
      if (!buyerCustomer) {
        console.warn(`[Order ${orderNum}] Skipping: Buyer customer not found in database for identifier "${buyerIdentifier}".`);
        continue;
      }

      const chain = await resolveSponsorChain(buyerCustomer);
      if (chain.length === 0) continue;

      const baseCalc = calculatePreGstCommissionBase(order);
      const base = baseCalc.base;
      if (base <= 0) {
        console.warn(`[Order ${orderNum}] Skipping: Pre-GST merchandise base is 0.`);
        continue;
      }

      for (const { level, customer: sponsor } of chain) {
        // Check if commission transaction already exists for this order & level
        const existingSnap = await adminDb.collection('commission_transactions')
          .where('orderId', '==', orderId)
          .where('level', '==', level)
          .limit(1)
          .get();

        if (!existingSnap.empty) {
          existingTransactionsSkipped++;
          continue;
        }

        const rate = await getEffectiveCommissionRate(level);
        const commissionAmount = roundCurrency((base * rate) / 100);
        if (commissionAmount <= 0) continue;

        const nowIso = new Date().toISOString();
        const txId = `ct-tx-${orderId}-L${level}`;
        const commissionTx = {
          id: txId,
          orderId: orderId,
          transactionId: `tx-${orderId}`,
          customerId: buyerCustomer.id,
          customerName: buyerCustomer.name || order.customerName || '',
          referrerCustomerId: sponsor.id,
          referrerAuthUid: sponsor.authUid || sponsor.id,
          referrerMobileNumber: sponsor.mobileNumber || '',
          level,
          commissionType: sponsor.id === buyerCustomer.id ? 'Referral Commission (Self/Organic)' : 'Referral Commission',
          commissionBaseAmount: base,
          commissionRate: rate,
          commissionAmount,
          reversedAmount: 0,
          status: 'Pending',
          createdAt: nowIso,
          updatedAt: nowIso
        };

        newTransactionsCreated++;
        totalCommissionGenerated = roundCurrency(totalCommissionGenerated + commissionAmount);
        walletIncrements[sponsor.id] = roundCurrency((walletIncrements[sponsor.id] || 0) + commissionAmount);

        console.log(`[Order ${orderNum}] -> Level ${level} Commission (${sponsor.name || sponsor.id}): Base ₹${base} @ ${rate}% = ₹${commissionAmount}`);

        if (!isDryRun) {
          await adminDb.collection('commission_transactions').doc(txId).set(commissionTx, { merge: true });
        }
      }
    }

    // Apply wallet balance increments to customer records
    for (const [custId, amount] of Object.entries(walletIncrements)) {
      customerWalletsUpdated++;
      console.log(`[Wallet Update] Customer ID ${custId}: +₹${amount}`);
      if (!isDryRun) {
        await adminDb.collection('customers').doc(custId).set({
          commissionPending: FieldValue.increment(amount)
        }, { merge: true });
      }
    }

    console.log('\n======================================================');
    console.log('               COMMISSION AUDIT & SUMMARY             ');
    console.log('======================================================');
    console.log(`Total Sales Orders Evaluated   : ${totalEvaluated}`);
    console.log(`Existing Transactions Skipped : ${existingTransactionsSkipped}`);
    console.log(`New Commission Txs Created    : ${newTransactionsCreated}`);
    console.log(`Customer Wallets Updated       : ${customerWalletsUpdated}`);
    console.log(`Total Commission Generated    : ₹${totalCommissionGenerated.toFixed(2)}`);
    console.log(`Dry Run Mode                   : ${isDryRun}`);
    console.log('======================================================\n');

  } catch (err: any) {
    console.error('[Reprocess Script Error]', err);
    process.exit(1);
  }
}

reprocessOrganicAndAllCommissions();
