import { adminDb } from './firebase-admin';

async function inspect() {
  try {
    const snap = await adminDb.collection('sales_orders').get();
    console.log(`Total sales_orders in database: ${snap.size}`);
    snap.docs.forEach((doc, idx) => {
      const data = doc.data();
      console.log(`Order #${idx + 1} (${doc.id}): customerId=${data.customerId}, customerName=${data.customerName}, mobile=${data.customerMobile}, email=${data.customerEmail}`);
    });
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}

inspect();
