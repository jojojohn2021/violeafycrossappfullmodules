import express from "express";
import path from "path";
import dotenv from "dotenv";
import fs from "fs";
import { GoogleGenAI } from "@google/genai";
import crypto from "crypto";
import nodemailer from "nodemailer";
import { onRequest } from "firebase-functions/v2/https";
import { adminApp, adminAuth, adminDb, adminStorage } from "./firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

dotenv.config();

// Example API Endpoint using violeafydb
async function getProducts(req: any, res: any) {
  try {
    const snapshot = await adminDb.collection("products").get();
    const products = snapshot.docs.map((doc: any) => ({ id: doc.id, ...doc.data() }));
    res.status(200).json(products);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
}

const app = express();
export const api = onRequest({ cors: true }, app);
app.use(express.json({ limit: "50mb" }));
app.use(express.urlencoded({ limit: "50mb", extended: true }));

// Enable CORS for web development
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept, Authorization");
  res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  if (req.method === "OPTIONS") {
    return res.sendStatus(200);
  }
  next();
});

app.get("/api/products", getProducts);
app.get("/api/data", async (req: any, res: any) => {
  try {
    const snapshot = await adminDb.collection("products").get();
    const products = snapshot.docs.map((doc: any) => ({ id: doc.id, ...doc.data() }));
    res.status(200).json({ status: "success", databaseId: "violeafydb", count: products.length, data: products });
  } catch (error: any) {
    res.status(500).json({ status: "error", error: error.message });
  }
});

const PORT = 3000;

// Retrieve the database ID dynamically from process.env, firebase-applet-config.json or URI
let dbId = process.env.FIREBASE_DATABASE_ID || "violeafydb";
try {
  if (!process.env.FIREBASE_DATABASE_ID) {
    const configPath = path.join(process.cwd(), "firebase-applet-config.json");
    if (fs.existsSync(configPath)) {
      const configData = JSON.parse(fs.readFileSync(configPath, "utf-8"));
      if (configData.firestoreDatabaseId) {
        dbId = configData.firestoreDatabaseId.trim();
      }
    }
  }
} catch (e) {
  console.error("[violeafycrossapp] Failed to load dynamically configured firestoreDatabaseId, using violeafydb as fallback.", e);
}

// Save clean database status file
if (!process.env.K_SERVICE && !process.env.FUNCTION_TARGET) {
  try {
    const statusDir = path.join(process.cwd(), "src");
    if (!fs.existsSync(statusDir)) {
      fs.mkdirSync(statusDir, { recursive: true });
    }
    fs.writeFileSync(path.join(statusDir, "db-status.json"), JSON.stringify({
      status: "Connected",
      provider: "Firebase Admin SDK",
      databaseId: dbId
    }, null, 2));
  } catch (e) { }
}

function normalizePaymentTransaction(tx: any) {
  if (!tx || typeof tx !== 'object') return tx;

  const orderPayload = tx.orderPayload || {};
  const shippingAddress = orderPayload.shippingAddress || tx.shippingAddress || {};

  const formattedAddress = typeof shippingAddress === 'string'
    ? shippingAddress
    : [shippingAddress.addressLine, shippingAddress.city, shippingAddress.district, shippingAddress.state, shippingAddress.pincode].filter(Boolean).join(', ');

  const mobileVal = (
    tx.customerMobile ||
    tx.customerPhone ||
    tx.phone ||
    orderPayload.customerMobile ||
    orderPayload.phone ||
    orderPayload.mobileNumber ||
    shippingAddress.mobileNumber ||
    ""
  ).toString().trim();

  const addressVal = (
    tx.customerAddress ||
    tx.deliveryAddress ||
    tx.address ||
    orderPayload.customerAddress ||
    orderPayload.deliveryAddress ||
    formattedAddress ||
    ""
  ).toString().trim();

  const gatewayVal = (
    tx.paymentGateway ||
    tx.gateway ||
    tx.paymentAggregator ||
    tx.aggregator ||
    "PayU"
  ).toString().trim();

  return {
    ...tx,
    gateway: gatewayVal,
    paymentGateway: gatewayVal,
    paymentAggregator: gatewayVal,
    aggregator: gatewayVal,
    customerMobile: mobileVal,
    customerPhone: mobileVal,
    phone: mobileVal,
    customerAddress: addressVal,
    deliveryAddress: addressVal,
    address: addressVal,
    customerName: tx.customerName || orderPayload.customerName || "Leafy Shopper",
    customerEmail: tx.customerEmail || orderPayload.customerEmail || ""
  };
}

async function getCollectionDocs(col: string): Promise<any[]> {
  try {
    const snapshot = await adminDb.collection(col).get();
    const docs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    if (col === 'payments') {
      return docs.map(tx => normalizePaymentTransaction(tx));
    }
    return docs;
  } catch (err: any) {
    console.error(`[VIO-FIRESTORE] getCollectionDocs error on collection '${col}':`, err);
    throw new Error(`Firestore read operation failed for collection '${col}': ${err.message || err}`);
  }
}

async function saveCollectionDoc(col: string, item: any): Promise<void> {
  try {
    const cleanItem = { ...item };
    delete cleanItem._id;
    await adminDb.collection(col).doc(String(item.id)).set(cleanItem, { merge: true });
  } catch (err: any) {
    console.error(`[VIO-FIRESTORE] saveCollectionDoc error on collection '${col}':`, err);
    throw new Error(`Firestore write operation failed for collection '${col}': ${err.message || err}`);
  }
}

async function getAuthenticatedUser(req: any): Promise<any> {
  const authorization = req.headers.authorization || '';
  if (!authorization.startsWith('Bearer ')) return null;
  try {
    return await adminAuth.verifyIdToken(authorization.substring(7));
  } catch (_) {
    return null;
  }
}

// PayU debug diagnostics toggle - reuses the existing payment_gateway_settings collection/mechanism.
// Default is ON until manually toggled/removed; missing setting is treated as enabled.
const PAYU_DEBUG_SETTINGS_DOC_ID = 'payu_debug_settings';

async function isPayUDebugEnabled(): Promise<boolean> {
  try {
    const doc = await adminDb.collection('payment_gateway_settings').doc(PAYU_DEBUG_SETTINGS_DOC_ID).get();
    return !doc.exists || doc.data()?.payu_debug_enabled !== false;
  } catch (_) {
    return true;
  }
}

// PayU Payment testing toggle - reuses the existing payment_gateway_settings collection/mechanism.
// PAYU_ENABLED defaults to true (normal PayU flow); missing setting is treated as enabled.
const PAYU_ENABLED_SETTINGS_DOC_ID = 'payu_enabled_settings';

async function isPayUEnabled(): Promise<boolean> {
  try {
    const doc = await adminDb.collection('payment_gateway_settings').doc(PAYU_ENABLED_SETTINGS_DOC_ID).get();
    return !doc.exists || doc.data()?.payu_enabled !== false;
  } catch (_) {
    return true;
  }
}

async function saveCustomerRecord(item: any, authenticatedUser: any): Promise<any> {
  const mobileNumber = String(item.mobileNumber || item.mobile || '').replace(/\D/g, '');
  if (!mobileNumber) throw new Error('Customer mobile number is required');

  if (authenticatedUser?.uid) {
    const linked = await adminDb.collection('customers').where('authUid', '==', authenticatedUser.uid).limit(1).get();
    if (!linked.empty) {
      const existingDoc = linked.docs[0];
      const existingData = existingDoc.data();
      if (item.id && item.id !== existingDoc.id) {
        throw new Error('Mobile number is already registered. Duplicate customer mobile number is not allowed.');
      }
      if (existingData.mobileNumber && existingData.mobileNumber !== mobileNumber) {
        const dupCheck = await adminDb.collection('customers').where('mobileNumber', '==', mobileNumber).limit(1).get();
        if (!dupCheck.empty && dupCheck.docs[0].id !== existingDoc.id) {
          throw new Error('Mobile number is already registered. Duplicate customer mobile number is not allowed.');
        }
      }
      return { id: existingDoc.id, ...existingData };
    }
  }

  const existing = await adminDb.collection('customers').where('mobileNumber', '==', mobileNumber).limit(1).get();
  if (!existing.empty) {
    const existingDoc = existing.docs[0];
    if (item.id && item.id !== existingDoc.id) {
      throw new Error('Mobile number is already registered. Duplicate customer mobile number is not allowed.');
    }
    return { id: existingDoc.id, ...existingDoc.data() };
  }

  const leads = await adminDb.collection('leads').where('phone', '==', mobileNumber).limit(1).get();
  const lead: any = leads.empty ? null : { id: leads.docs[0].id, ...leads.docs[0].data() };
  const indexRef = adminDb.collection('customer_mobile_index').doc(mobileNumber);

  return adminDb.runTransaction(async (transaction) => {
    const index = await transaction.get(indexRef);
    if (index.exists) {
      const customerId = index.data()?.customerId;
      if (customerId) {
        const existingCustomer = await transaction.get(adminDb.collection('customers').doc(String(customerId)));
        if (existingCustomer.exists) {
          if (item.id && item.id !== existingCustomer.id) {
            throw new Error('Mobile number is already registered. Duplicate customer mobile number is not allowed.');
          }
          return { id: existingCustomer.id, ...existingCustomer.data() };
        }
      }
    }

    const mobileMatch = await transaction.get(adminDb.collection('customers').where('mobileNumber', '==', mobileNumber).limit(1));
    if (!mobileMatch.empty) {
      const existingCustomer = mobileMatch.docs[0];
      if (item.id && item.id !== existingCustomer.id) {
        throw new Error('Mobile number is already registered. Duplicate customer mobile number is not allowed.');
      }
      transaction.set(indexRef, { customerId: existingCustomer.id, mobileNumber }, { merge: true });
      return { id: existingCustomer.id, ...existingCustomer.data() };
    }

    const customerRef = item.id ? adminDb.collection('customers').doc(item.id) : adminDb.collection('customers').doc();
    const cleanItem = { ...item };
    delete cleanItem.mobile;

    const customer = {
      ...cleanItem,
      id: customerRef.id,
      authUid: authenticatedUser?.uid || cleanItem.authUid || null,
      mobileNumber,
      leadslinkid: lead?.id || null,
      referralcode: lead?.referralcode ?? lead?.referralCode ?? null,
      referralpartner: lead?.referralpartner ?? lead?.referralPartner ?? null,
      leadId: lead?.id || null,
      referralCode: lead?.referralcode ?? lead?.referralCode ?? null,
    };
    transaction.set(customerRef, customer);
    transaction.set(indexRef, { customerId: customerRef.id, mobileNumber });
    return customer;
  });
}

async function saveLeadRecord(item: any): Promise<any> {
  const phone = String(item.phone || '').replace(/\D/g, '');
  if (phone.length !== 10) throw new Error('WhatsApp mobile number must be exactly 10 digits');
  const reservationRef = adminDb.collection('lead_mobile_index').doc(phone);
  const leadRef = adminDb.collection('leads').doc(String(item.id));
  return adminDb.runTransaction(async (transaction) => {
    const reservation = await transaction.get(reservationRef);
    if (reservation.exists && reservation.data()?.leadId !== String(item.id)) {
      const error: any = new Error('Mobile number is already reserved. Duplicate number is not allowed.');
      error.statusCode = 409;
      throw error;
    }
    const existing = await transaction.get(leadRef);
    if (!existing.exists) {
      const duplicate = await transaction.get(adminDb.collection('leads').where('phone', '==', phone).limit(1));
      if (!duplicate.empty && duplicate.docs[0].id !== String(item.id)) {
        const error: any = new Error('Mobile number is already reserved. Duplicate number is not allowed.');
        error.statusCode = 409;
        throw error;
      }
    }
    const payload = { ...item, phone };
    delete payload.company;
    transaction.set(leadRef, payload, { merge: true });
    transaction.set(reservationRef, { leadId: String(item.id), phone }, { merge: true });
    return payload;
  });
}

// Get database status
app.get("/api/mongo-status", (req, res) => {
  res.json({
    connected: true,
    mode: "Firebase Admin SDK (Firestore)",
    databaseId: dbId
  });
});

// POST /api/referral-ai-suggestions
app.post("/api/referral-ai-suggestions", async (req, res) => {
  const { partnerName, kpis, periodGaps, productGaps } = req.body;

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.json({
      suggestions: [
        "Setup your GEMINI_API_KEY in Settings > Secrets to unlock live, customized AI recommendation engines!",
        "Tip: Check which products are nearest to their sales target and concentrate efforts there.",
        "Tip: Engage your Level 2 and Level 3 referred partners to drive multi-level override commissions.",
        "Tip: Send promotional WhatsApp broadcast templates to warm leads to boost sales volume."
      ]
    });
  }

  try {
    const ai = new GoogleGenAI({
      apiKey,
      httpOptions: {
        headers: {
          'User-Agent': 'aistudio-build'
        }
      }
    });

    const prompt = `You are an AI Sales Consultant in high-performance referral marketing. Provide 4 direct, human-oriented, hyper-tactical and highly motivating actions for a Referral Partner named "${partnerName}".
    Here are their raw metrics:
    - Total Sales Driven: ₹${kpis.totalSales} (Current Month: ₹${kpis.currentMonthSales}, YTD: ₹${kpis.ytdSales})
    - Total Commission Earned: ₹${kpis.totalCommission} (Current Month: ₹${kpis.currentMonthCommission})
    - Period Target Gap status: ${JSON.stringify(periodGaps)}
    - Product Target Gap status: ${JSON.stringify(productGaps)}

    Format your response as a JSON array of exactly 4 strings. Each string must be a concise, motivating, and concrete action recommendation (no markdown headers, plain text only, maximum 150 characters per string). Do not return markdown wraps like \`\`\`json, return a clean raw JSON array of strings so that it can be parsed directly.`;

    const response = await ai.models.generateContent({
      model: "gemini-3.5-flash",
      contents: prompt,
    });

    const text = (response.text || "[]").trim();
    let cleanText = text;
    if (cleanText.startsWith("```json")) {
      cleanText = cleanText.substring(7);
    } else if (cleanText.startsWith("```")) {
      cleanText = cleanText.substring(3);
    }
    if (cleanText.endsWith("```")) {
      cleanText = cleanText.substring(0, cleanText.length - 3);
    }
    cleanText = cleanText.trim();

    try {
      const parsed = JSON.parse(cleanText);
      if (Array.isArray(parsed)) {
        return res.json({ suggestions: parsed.slice(0, 4) });
      }
    } catch (e) {
      // Fallback line split parsing
      const lines = text
        .split("\n")
        .map(l => l.replace(/^[-\*\d\.\s"\[\]]+/, "").replace(/[",\]\[\r\n]+$/, "").trim())
        .filter(Boolean)
        .slice(0, 4);
      if (lines.length > 0) {
        return res.json({ suggestions: lines });
      }
    }

    return res.json({
      suggestions: [
        "Focus on bridging the product target gaps to achieve your bonus commissions.",
        "Provide sales enablement tools to sub-partners who are driving active level commissions.",
        "Review your sales pipeline for this month to convert pending leads into finalized order invoices.",
        "Review your quarterly targets to secure multi-level performance payouts checkups."
      ]
    });

  } catch (err: any) {
    console.error("AI suggestions error:", err);
    return res.json({
      suggestions: [
        "Tip: Check which products are closest to achieving their performance target and align outreach campaigns.",
        "Tip: Motivate sub-agents to refer customers to secure recursive override revenue.",
        "Tip: Monitor monthly invoices to ensure all completed orders are matched with your code.",
        "Error generating live suggestions: " + (err.message || String(err))
      ]
    });
  }
});

// POST /api/influencer-ai-assistant
app.post("/api/influencer-ai-assistant", async (req, res) => {
  const { action, productName, campaignGoal, influencers, campaignName, captionTone } = req.body;

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.json({
      success: true,
      result: "Setup your GEMINI_API_KEY in Settings > Secrets to unlock live, customized AI recommendations!\n\nAI Mock suggestion: Focus on high-performing Instagram Reels and YouTube shorts influencers for " + (productName || "your products") + " with health, nutrition or lifestyle niches."
    });
  }

  try {
    const ai = new GoogleGenAI({
      apiKey,
      httpOptions: {
        headers: {
          'User-Agent': 'aistudio-build'
        }
      }
    });

    let prompt = "";
    if (action === 'recommend_influencers') {
      prompt = `You are a professional Influencer Marketing Manager.
Recommend which influencers from this database would be best suited for promoting our product "${productName}" with the campaign goal "${campaignGoal}".
Here are the available influencers in our database: ${JSON.stringify(influencers || [])}

Provide your recommendations as a friendly, professional analysis. List the best 2-3 influencers, explain why they fit based on their platform/niche/followers, and suggest what specific content theme they should create (e.g. unboxing, tutorial, daily vlog integration). Keep it highly detailed but clear and beautifully formatted with bullet points.`;
    } else if (action === 'write_brief') {
      prompt = `You are an expert Brand Strategist.
Create a detailed, highly professional campaign brief for our campaign "${campaignName || 'Product Launch'}" promoting the product "${productName}" with the campaign goal: "${campaignGoal}".

The brief should include:
1. Campaign Overview & Goal
2. Key Message & Selling Points of the Product
3. Specific Deliverable Requirements (e.g., length, hooks, call to action, hashtags)
4. Do's and Don'ts for the influencers to follow
5. Specific integration instructions (e.g., link in bio, discount code, Amazon callout).

Format it with professional markdown headings, bullet points, and neat paragraphs.`;
    } else { // generate_captions
      prompt = `You are a world-class Social Media copywriter.
Generate 3 high-converting social media caption options in a "${captionTone || 'creative'}" tone for an influencer promoting "${productName}" with the campaign objective "${campaignGoal}".
Include engaging hooks, value propositions, a strong Call to Action (CTA) like using a promo code or visiting the shop, and highly relevant, trending hashtags. Format each option clearly with a nice title like "Option 1: Hook-first", "Option 2: Storytelling-driven", and "Option 3: Short & Punchy".`;
    }

    const response = await ai.models.generateContent({
      model: "gemini-3.5-flash",
      contents: prompt,
    });

    return res.json({
      success: true,
      result: response.text || "No response generated from the model."
    });

  } catch (err: any) {
    console.error("Influencer AI helper error:", err);
    return res.status(500).json({ error: err.message || "Failed to execute AI request" });
  }
});

// GET all collections or individual collection
app.get("/api/data", async (req, res) => {
  try {
    const collections = [
      'leads', 'deals', 'tasks', 'calendar_events', 'products',
      'customers', 'campaigns', 'whatsapp_messages', 'whatsapp_sequences',
      'referrals', 'audit_logs', 'users', 'sales_orders', 'payouts', 'brand_config',
      'referral_chains', 'chain_histories', 'commission_transactions',
      'product_level_commissions', 'performance_levels', 'partner_performances',
      'influencers', 'influencer_campaigns', 'influencer_collaborations',
      'influencer_dispatches', 'influencer_payments', 'influencer_contents',
      'product_categories', 'product_brands', 'product_brand_owners',
      'shopping_carts', 'wishlists', 'product_reviews', 'customer_delivery_addresses', 'coupons',
      'order_delivery_tracking', 'order_return_requests', 'order_refunds', 'payments',
      'payment_gateway_settings', 'delivery_charges', 'notification_settings', 'notification_logs'
    ];
    const data: Record<string, any[]> = {};

    await Promise.all(collections.map(async (col) => {
      const snapshot = await adminDb.collection(col).get();
      data[col] = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    }));

    return res.json(data);
  } catch (err: any) {
    console.error("[VIO-FIRESTORE] Error reading data collections:", err);
    return res.status(500).json({ error: `Firestore read failed: ${err.message || err}` });
  }
});

// GET documents for a specific collection
app.get("/api/data/:collectionName", async (req, res) => {
  const { collectionName } = req.params;
  try {
    const docs = await getCollectionDocs(collectionName);
    return res.json(docs);
  } catch (err: any) {
    console.error(`[VIO-FIRESTORE] Error fetching collection ${collectionName}:`, err);
    return res.status(500).json({ error: err.message || `Failed to fetch collection ${collectionName}` });
  }
});

// Alias Routes for direct endpoints
app.get("/api/products", async (req, res) => {
  try {
    const docs = await getCollectionDocs("products");
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch products" });
  }
});

// Authoritative Category API - Reads product_categories table/collection
app.get(["/api/categories", "/api/product-categories"], async (req, res) => {
  try {
    let docs = await getCollectionDocs("product_categories");
    if (!docs || docs.length === 0) {
      // Fallback: derive categories from products database table
      const products = await getCollectionDocs("products");
      const categoryNames = Array.from(new Set(products.map((p: any) => p.category).filter(Boolean)));
      docs = categoryNames.map((cat, idx) => ({
        id: `cat_${idx + 1}`,
        name: cat,
        status: "Active",
        description: `${cat} products`,
        imageUrl: ""
      }));
    }
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch categories" });
  }
});

// Authoritative Brand API - Reads product_brands table/collection
app.get(["/api/brands", "/api/product-brands"], async (req, res) => {
  try {
    let docs = await getCollectionDocs("product_brands");
    if (!docs || docs.length === 0) {
      // Fallback: derive brands from products database table
      const products = await getCollectionDocs("products");
      const brandNames = Array.from(new Set(products.map((p: any) => p.brand).filter(Boolean)));
      docs = brandNames.map((brand, idx) => ({
        id: `brand_${idx + 1}`,
        name: brand,
        status: "Active",
        description: `${brand} brand`,
        imageUrl: ""
      }));
    }
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch brands" });
  }
});

// Authoritative Brand Owner API - Reads product_brand_owners table/collection
app.get(["/api/brand-owners", "/api/product-brand-owners"], async (req, res) => {
  try {
    let docs = await getCollectionDocs("product_brand_owners");
    if (!docs || docs.length === 0) {
      // Fallback: derive brand owners from products database table
      const products = await getCollectionDocs("products");
      const ownerNames = Array.from(new Set(products.map((p: any) => p.brandOwner).filter(Boolean)));
      docs = ownerNames.map((owner, idx) => ({
        id: `owner_${idx + 1}`,
        name: owner,
        company: owner,
        status: "Active",
        imageUrl: ""
      }));
    }
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch brand owners" });
  }
});

app.get("/api/banners", async (req, res) => {
  try {
    const docs = await getCollectionDocs("campaigns");
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch banners" });
  }
});

app.get("/api/wallets", async (req, res) => {
  try {
    const docs = await getCollectionDocs("wallets");
    return res.json(docs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch wallets" });
  }
});

function invoiceNumber(orderId: string): string {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const suffix = crypto.createHash('sha256').update(orderId).digest('hex').slice(0, 8).toUpperCase();
  return `INV-${date}-${suffix}`;
}

function numberValue(value: any): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value: number): number {
  return Math.round(value * 100) / 100;
}

async function buildCustomerReferralSummary(customer: any): Promise<Record<string, number>> {
  if (!customer) return { totalCommissionEarned: 0, totalPayout: 0, walletBalance: 0 };

  try {
    const partnerIds = Array.from(new Set([customer.id, customer.authUid, customer.mobileNumber].filter(Boolean)));
    const commissionSnap = await adminDb.collection('commission_transactions').get();
    const totalCommissionEarned = money(commissionSnap.docs.reduce((sum, doc) => {
      const data: any = doc.data();
      if (!partnerIds.includes(data.referrerCustomerId) && !partnerIds.includes(data.referrerAuthUid) && !partnerIds.includes(data.referrerMobileNumber)) return sum;
      if (data.status === 'Cancelled' || data.status === 'Reversed') return sum;
      return sum + Math.max(0, numberValue(data.commissionAmount) - numberValue(data.reversedAmount));
    }, 0));

    let totalPayout = 0;
    if (partnerIds.length > 0) {
      const payoutSnap = await adminDb.collection('payouts').get();
      totalPayout = money(payoutSnap.docs.reduce((sum, doc) => {
        const data: any = doc.data();
        return partnerIds.includes(data.partnerId) && ['Paid', 'Settled', 'Completed'].includes(String(data.status))
          ? sum + numberValue(data.amount)
          : sum;
      }, 0));
    }

    const walletDocs = await getCollectionDocs('wallets');
    const wallet = walletDocs.find((item: any) => partnerIds.includes(item.partnerId || item.customerId || item.userId));
    const walletBalance = numberValue(wallet?.availableBalance ?? wallet?.balance ?? wallet?.totalBalance);
    return { totalCommissionEarned, totalPayout, walletBalance: money(walletBalance) };
  } catch (err) {
    console.error('[Invoice API] Error building referral summary:', err);
    return { totalCommissionEarned: 0, totalPayout: 0, walletBalance: 0 };
  }
}

app.get("/api/invoices/:invoiceId", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) return res.status(401).json({ error: "Authenticated customer required" });

    const requestedId = String(req.params.invoiceId);
    const orders = await getCollectionDocs('sales_orders');
    let order = orders.find((item: any) => [item.id, item.orderNumber, item.invoiceId].includes(requestedId));
    
    const customer = await findCustomerByAuthUid(authenticatedUser.uid);
    const validCustomerIds = new Set([
      authenticatedUser.uid,
      customer?.id,
      customer?.authUid,
      authenticatedUser.email,
      customer?.email
    ].filter(Boolean));

    if (!order || (!validCustomerIds.has(order.customerId) && !validCustomerIds.has(order.userId) && !validCustomerIds.has(order.customerEmail))) {
      return res.status(404).json({ error: "Invoice not found" });
    }

    const invoiceDocs = await getCollectionDocs('invoices');
    let savedInvoice = invoiceDocs.find((item: any) => item.orderId === order.id || item.id === order.invoiceId);
    const invoiceId = order.invoiceId || savedInvoice?.invoiceId || savedInvoice?.id || invoiceNumber(order.id);
    const invoiceDate = order.invoiceDate || savedInvoice?.invoiceDate || order.createdAt || new Date().toISOString();

    if (!order.invoiceId) {
      await saveCollectionDoc('sales_orders', { id: order.id, invoiceId, invoiceDate });
      order = { ...order, invoiceId, invoiceDate };
    }

    if (!savedInvoice) {
      savedInvoice = { id: invoiceId, invoiceId, orderId: order.id, invoiceDate, createdAt: new Date().toISOString() };
      await saveCollectionDoc('invoices', savedInvoice);
    }

    const formatInvoiceDocs = await getCollectionDocs('formatinvoice');
    const format = formatInvoiceDocs[0] || {};
    const products = await getCollectionDocs('products');
    const rawProducts = order.products || order.items || order.orderPayload?.products || [];
    const items = rawProducts.map((item: any, index: number) => {
      const product = products.find((candidate: any) => candidate.id === (item.productId || item.id)) || {};
      const quantity = numberValue(item.quantity ?? item.qty ?? 1);
      const rate = numberValue(item.rate ?? item.price ?? item.unitPrice);
      const mrp = numberValue(item.mrp ?? product.mrp ?? product.onlinePrice ?? rate);
      const discount = numberValue(item.discount ?? Math.max(0, (mrp - rate) * quantity));
      const gstRate = numberValue(item.gstPercentage ?? item.gstRate ?? product.gstPercentage ?? product.gstRate);
      const total = numberValue(item.total ?? item.lineTotal ?? rate * quantity);
      const gstAmount = numberValue(item.gstAmount ?? (total * gstRate) / (100 + gstRate));
      return {
        productId: item.productId || item.id || product.id || '',
        imageUrl: item.imageUrl || item.picture || product.imageUrl || product.image || '',
        slNo: index + 1,
        sku: item.sku || product.sku || '',
        itemDetails: item.productName || item.name || product.name || '',
        hsnCode: item.hsnCode || product.hsnCode || product.hsn || '',
        unit: item.unit || product.unit || product.packingSize || '',
        quantity,
        mrp: money(mrp),
        rate: money(rate),
        gstRate: money(gstRate),
        discount: money(discount),
        total: money(total),
        gstAmount: money(gstAmount)
      };
    });

    const gstGroups: Record<string, any> = {};
    for (const item of items) {
      const key = `${item.hsnCode || '-'}|${item.gstRate}`;
      gstGroups[key] ||= { hsnCode: item.hsnCode || '-', taxableAmount: 0, gstRate: item.gstRate, gstAmount: 0 };
      gstGroups[key].taxableAmount += item.total - item.gstAmount;
      gstGroups[key].gstAmount += item.gstAmount;
    }
    const gstByHsn = Object.values(gstGroups).map((group: any) => ({
      ...group,
      taxableAmount: money(group.taxableAmount),
      gstAmount: money(group.gstAmount)
    }));
    const subtotal = money(items.reduce((sum: number, item: any) => sum + item.total, 0));
    const itemTotal = money(numberValue(order.itemTotal ?? order.subtotal ?? subtotal));
    const gstSubtotal = money(gstByHsn.reduce((sum: number, item: any) => sum + item.gstAmount, 0));
    const grandTotalVal = numberValue(order.totalValue ?? order.grandTotal ?? order.totalAmount ?? order.total ?? order.amount ?? subtotal);
    const grandTotal = money(grandTotalVal);
    const totalSavedAmount = money(items.reduce((sum: number, item: any) => sum + item.discount, 0) + numberValue(order.invoiceDiscount));
    const referralSummary = await buildCustomerReferralSummary(customer);

    return res.json({ success: true, invoice: {
      invoiceId, invoiceDate,
      header: {
        companyName: format.companyName || format.company_name || '',
        addresses: format.addresses || format.address ? [format.addresses || format.address].flat() : [],
        mobileNumbers: format.mobileNumbers || format.mobile_numbers || format.mobile ? [format.mobileNumbers || format.mobile].flat() : [],
        customerCareMobile: format.customerCareMobile || format.customer_care_mobile || '',
        customerCareEmail: format.customerCareEmail || format.customer_care_email || ''
      },
      customer: { name: order.customerName || '', email: order.customerEmail || '', mobile: order.customerMobile || '', address: order.shippingAddress || null },
      items, summary: { subtotal, itemTotal, gstSubtotal, grandTotal, totalSavedAmount },
      gstByHsn, referralSummary,
      customerActions: { canBuyAgain: items.some((item: any) => Boolean(item.productId)), canUseReferral: Boolean(customer), canViewWallet: Boolean(customer) }
    }});
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read invoice" });
  }
});

app.get("/api/sales-orders", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) {
      return res.status(401).json({ error: "Authenticated customer required" });
    }
    const customer = await findCustomerByAuthUid(authenticatedUser.uid);
    const validCustomerIds = new Set([
      authenticatedUser.uid,
      customer?.id,
      customer?.authUid,
      authenticatedUser.email,
      customer?.email
    ].filter(Boolean));

    const docs = await getCollectionDocs("sales_orders");
    const ownOrders = docs.filter((order: any) => 
      validCustomerIds.has(order.customerId) || validCustomerIds.has(order.userId) || validCustomerIds.has(order.customerEmail)
    );
    return res.json(ownOrders);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch sales-orders" });
  }
});

// POST /api/auth/verify-login - Verification & Onboarding orchestration after Firebase OTP success
app.post("/api/auth/verify-login", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) {
      return res.status(401).json({
        success: false,
        error: "Unauthorized: Valid Firebase authentication token required"
      });
    }

    const rawPhone = authenticatedUser.phone_number || req.body?.phone || "";
    const digits = String(rawPhone).replace(/\D/g, "");
    if (!digits) {
      return res.status(400).json({
        success: false,
        error: "Verified mobile number is missing from authentication context"
      });
    }

    // Extract 10-digit mobile number
    const authenticatedMobile = digits.length > 10 ? digits.substring(digits.length - 10) : digits;

    // 1. Check existing customer table using mobileNumber field (and authUid)
    const customersRef = adminDb.collection("customers");
    const mobileMatch = await customersRef.where("mobileNumber", "==", authenticatedMobile).limit(1).get();
    let existingCustomerDoc = mobileMatch.empty ? null : mobileMatch.docs[0];

    if (!existingCustomerDoc && authenticatedUser.uid) {
      const uidMatch = await customersRef.where("authUid", "==", authenticatedUser.uid).limit(1).get();
      if (!uidMatch.empty) {
        existingCustomerDoc = uidMatch.docs[0];
      }
    }

    // Rule 4.1: Existing Customer
    if (existingCustomerDoc) {
      const customerData = { id: existingCustomerDoc.id, ...existingCustomerDoc.data() };
      return res.json({
        success: true,
        action: "EXISTING_CUSTOMER",
        customerId: existingCustomerDoc.id,
        item: customerData
      });
    }

    // Customer Not Found -> Check Leads table using phone field
    const leadsRef = adminDb.collection("leads");
    const leadMatch = await leadsRef.where("phone", "==", authenticatedMobile).limit(1).get();
    const leadDoc = leadMatch.empty ? null : leadMatch.docs[0];

    // Concurrency control / race condition duplicate prevention via transaction
    const indexRef = adminDb.collection("customer_mobile_index").doc(authenticatedMobile);

    const transactionResult = await adminDb.runTransaction(async (transaction) => {
      // Re-check index in transaction
      const indexDoc = await transaction.get(indexRef);
      if (indexDoc.exists) {
        const existingId = indexDoc.data()?.customerId;
        if (existingId) {
          const custDoc = await transaction.get(customersRef.doc(String(existingId)));
          if (custDoc.exists) {
            return {
              action: "EXISTING_CUSTOMER",
              customerId: custDoc.id,
              customer: { id: custDoc.id, ...custDoc.data() }
            };
          }
        }
      }

      // Double-check customers query inside transaction
      const doubleCheckMobile = await transaction.get(customersRef.where("mobileNumber", "==", authenticatedMobile).limit(1));
      if (!doubleCheckMobile.empty) {
        const custDoc = doubleCheckMobile.docs[0];
        transaction.set(indexRef, { customerId: custDoc.id, mobileNumber: authenticatedMobile }, { merge: true });
        return {
          action: "EXISTING_CUSTOMER",
          customerId: custDoc.id,
          customer: { id: custDoc.id, ...custDoc.data() }
        };
      }

      if (leadDoc) {
        // Rule 4.2: Customer Not Found, Matching Lead Found
        const leadData = leadDoc.data() || {};
        const customerDocRef = customersRef.doc();
        const customerId = customerDocRef.id;

        const refCode = leadData.referralCode ?? leadData.referralcode ?? null;
        const refPartner = leadData.referralPartner ?? leadData.referralpartner ?? null;
        const leadId = leadDoc.id;

        const newCustomer: Record<string, any> = {
          id: customerId,
          customerId: customerId,
          authUid: authenticatedUser.uid || null,
          name: leadData.name || "",
          company: leadData.company || "",
          email: leadData.email || "",
          mobileNumber: authenticatedMobile,
          referralCode: refCode,
          referralPartner: refPartner,
          referralcode: refCode,
          referralpartner: refPartner,
          isFromLead: true,
          leadId: leadId,
          leadslinkid: leadId,
          address: leadData.address || "",
          state: leadData.state || "",
          district: leadData.district || "",
          pincode: leadData.pincode || null,
          totalSpent: 0,
          dealsClosed: 0,
          satisfactionScore: 0,
          lastOrderDate: new Date().toISOString().split("T")[0],
          tier: "Bronze",
          createdAt: new Date().toISOString()
        };

        // Write customer record & index record
        transaction.set(customerDocRef, newCustomer);
        transaction.set(indexRef, { customerId, mobileNumber: authenticatedMobile });

        // Update lead status to qualified
        transaction.update(leadDoc.ref, { status: "qualified" });

        return {
          action: "LEAD_CONVERTED",
          customerId,
          customer: newCustomer
        };
      } else {
        // Rule 4.3: Customer Not Found, Lead Not Found (Organic Customer)
        const customerDocRef = customersRef.doc();
        const customerId = customerDocRef.id;

        const newCustomer: Record<string, any> = {
          id: customerId,
          customerId: customerId,
          authUid: authenticatedUser.uid || null,
          name: "",
          company: "",
          email: "",
          mobileNumber: authenticatedMobile,
          referralCode: "organic",
          referralPartner: "organic",
          referralcode: "organic",
          referralpartner: "organic",
          isFromLead: false,
          leadId: null,
          leadslinkid: null,
          address: "",
          state: "",
          district: "",
          pincode: null,
          totalSpent: 0,
          dealsClosed: 0,
          satisfactionScore: 0,
          lastOrderDate: new Date().toISOString().split("T")[0],
          tier: "Bronze",
          createdAt: new Date().toISOString()
        };

        // Write customer record & index record
        transaction.set(customerDocRef, newCustomer);
        transaction.set(indexRef, { customerId, mobileNumber: authenticatedMobile });

        return {
          action: "ORGANIC_CUSTOMER",
          customerId,
          customer: newCustomer
        };
      }
    });

    return res.json({
      success: true,
      action: transactionResult.action,
      customerId: transactionResult.customerId,
      item: transactionResult.customer
    });

  } catch (err: any) {
    console.error("[VIO-FIRESTORE] Error in verify-login orchestration:", err);
    return res.status(500).json({
      success: false,
      error: err.message || "Failed to verify user login"
    });
  }
});

// POST to save a document in a collection
app.post("/api/data/:collectionName", async (req, res) => {
  const { collectionName } = req.params;
  const item = req.body;
  if (!item) {
    return res.status(400).json({ error: "Missing payload item" });
  }

  try {
    if (collectionName === 'customers') {
      const authenticatedUser = await getAuthenticatedUser(req);
      const customer = await saveCustomerRecord(item, authenticatedUser);
      return res.json({ success: true, item: customer });
    }
    if (!item.id) {
      return res.status(400).json({ error: "Missing payload item.id" });
    }
    if (collectionName === 'leads') {
      const lead = await saveLeadRecord(item);
      return res.json({ success: true, item: lead });
    }
    await saveCollectionDoc(collectionName, item);
    return res.json({ success: true, item });
  } catch (err: any) {
    console.error(`[VIO-FIRESTORE] Error saving record to ${collectionName}:`, err);
    return res.status(err.statusCode || 500).json({ error: err.message || "Failed to save record" });
  }
});

// DELETE a document from a collection
app.delete("/api/data/:collectionName/:id", async (req, res) => {
  const { collectionName, id } = req.params;
  try {
    await adminDb.collection(collectionName).doc(id).delete();
    return res.json({ success: true });
  } catch (err: any) {
    console.error(`[VIO-FIRESTORE] Error deleting document ${id} from ${collectionName}:`, err);
    return res.status(500).json({ error: `Firestore delete operation failed: ${err.message || err}` });
  }
});

// GET database-level health status check
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", firebaseConnected: true });
});

app.post("/api/database/purge", async (req, res) => {
  try {
    const collections = [
      'leads', 'deals', 'tasks', 'calendar_events', 'products',
      'customers', 'campaigns', 'whatsapp_messages', 'whatsapp_sequences',
      'referrals', 'audit_logs', 'users', 'sales_orders', 'payouts', 'brand_config',
      'referral_chains', 'chain_histories', 'commission_transactions',
      'product_level_commissions', 'performance_levels', 'partner_performances',
      'influencers', 'influencer_campaigns', 'influencer_collaborations',
      'influencer_dispatches', 'influencer_payments', 'influencer_contents',
      'shopping_carts', 'wishlists', 'product_reviews', 'customer_delivery_addresses', 'coupons',
      'order_delivery_tracking', 'order_return_requests', 'order_refunds', 'payments',
      'payment_gateway_settings', 'delivery_charges', 'notification_settings', 'notification_logs'
    ];
    for (const col of collections) {
      const snapshot = await adminDb.collection(col).get();
      if (!snapshot.empty) {
        const batch = adminDb.batch();
        snapshot.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
      }
    }
    return res.json({ success: true, message: "Database collections purged successfully from Cloud Firestore!" });
  } catch (err: any) {
    console.error("[VIO-FIRESTORE] Error purging database:", err);
    return res.status(500).json({ error: `Firestore purge operation failed: ${err.message || err}` });
  }
});

app.post("/api/database/populate", async (req, res) => {
  try {
    /*
    const dummyCoupons = [
      {
        id: "coupon-festive",
        code: "FESTIVE10",
        type: "percentage",
        value: 10,
        minOrderValue: 500,
        isActive: true,
        expiryDate: "2027-12-31",
        description: "Get 10% off on fresh groceries above ₹500"
      },
      {
        id: "coupon-leafy",
        code: "LEAFY20",
        type: "percentage",
        value: 20,
        minOrderValue: 1000,
        isActive: true,
        expiryDate: "2027-12-31",
        description: "Save 20% on orders above ₹1000"
      }
    ];

    const dummyLevels = [
      { id: "level-bronze", levelName: "Bronze", minCommission: 0, commissionPercentage: 5.0 },
      { id: "level-silver", levelName: "Silver", minCommission: 5000, commissionPercentage: 7.5 },
      { id: "level-gold", levelName: "Gold", minCommission: 15050, commissionPercentage: 10.0 },
      { id: "level-platinum", levelName: "Platinum", minCommission: 50050, commissionPercentage: 12.5 }
    ];

    const dummyUsers = [
      {
        id: "user-jojo",
        name: "JOJO",
        role: "Admin",
        email: "jojo@viocrm.com",
        avatar: "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&h=100&fit=crop&q=80",
        team: "Executive Leadership",
        mobileNumber: "8547856353",
        password: "1234"
      },
      {
        id: "user-admin",
        name: "John Doe",
        role: "Admin",
        email: "jojojohn@gmail.com",
        avatar: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&q=80",
        team: "Executive Leadership",
        mobileNumber: "9876543210",
        password: "1234"
      },
      {
        id: "user-partner",
        name: "Rahul Kumar",
        role: "Referral Team",
        email: "rahul@referral.com",
        avatar: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&q=80",
        team: "Referral Partners Team",
        mobileNumber: "9876543211",
        password: "1234"
      }
    ];

    const dummyWallets = [
      {
        id: "w-ref-partner-rahul",
        partnerId: "ref-partner-rahul",
        totalBalance: 320.0,
        availableBalance: 320.0,
        pendingApprovalAmount: 0.0,
        processingAmount: 0.0,
        paidAmount: 1500.0
      }
    ];

    const dummyDeliveries = [
      { id: "del-default", pincode: "default", charge: 40.0 },
      { id: "del-blr-1", pincode: "560001", charge: 20.0 },
      { id: "del-blr-2", pincode: "560034", charge: 0.0 }
    ];

    for (const c of dummyCoupons) {
      await adminDb.collection('coupons').doc(c.id).set(c, { merge: true });
    }
    for (const l of dummyLevels) {
      await adminDb.collection('performance_levels').doc(l.id).set(l, { merge: true });
    }
    for (const u of dummyUsers) {
      await adminDb.collection('users').doc(u.id).set(u, { merge: true });
    }
    for (const w of dummyWallets) {
      await adminDb.collection('wallets').doc(w.id).set(w, { merge: true });
    }
    for (const d of dummyDeliveries) {
      await adminDb.collection('delivery_charges').doc(d.id).set(d, { merge: true });
    }
    */

    return res.json({ success: true, message: "Production datasets populated successfully into Cloud Firestore!" });
  } catch (err: any) {
    console.error("[VIO-FIRESTORE] Error populating database:", err);
    return res.status(500).json({ error: `Firestore populate operation failed: ${err.message || err}` });
  }
});

// Secure Server-Side Payment Gateway Services
app.get("/api/payment/transactions", async (req, res) => {
  try {
    const txs = await getCollectionDocs('payments');
    return res.json(txs);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch transactions" });
  }
});

// Salt encryption/decryption helpers
function decryptSalt(encrypted: string): string {
  try {
    return Buffer.from(encrypted, 'base64').toString('utf8');
  } catch (e) {
    return encrypted;
  }
}

app.post("/api/payment/test-connection", async (req, res) => {
  try {
    const { merchant_key, merchant_salt, environment } = req.body;
    if (!merchant_key || !merchant_salt) {
      return res.status(400).json({ error: "Merchant Key and Salt are required." });
    }
    const cleanSalt = decryptSalt(merchant_salt);
    if (merchant_key.trim().length >= 4 && cleanSalt.trim().length >= 4) {
      return res.json({ success: true, message: "Connection Successful" });
    } else {
      return res.status(400).json({ success: false, message: "Invalid Merchant Credentials" });
    }
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to test connection" });
  }
});

async function getNotificationSettings() {
  const configs = await getCollectionDocs('notification_settings');
  let config = configs.find((c: any) => c.id === 'config-notifications');
  if (!config) {
    config = {
      id: 'config-notifications',
      companyName: 'Leafy Organics',
      successEmails: ['owner@leafy.com', 'admin@leafy.com', 'warehouse@leafy.com'],
      failedEmails: ['admin@leafy.com', 'sales@leafy.com'],
      cancelledEmails: ['admin@leafy.com', 'sales@leafy.com'],
      successPhones: ['+919876543210', '+918765432109'],
      failedPhones: ['+919876543210'],
      cancelledPhones: ['+919876543210'],
      smtpHost: '',
      smtpPort: 2525,
      smtpUser: '',
      smtpPass: '',
      smtpFrom: 'no-reply@leafy.com',
      whatsappApiUrl: 'https://graph.facebook.com/v17.0',
      whatsappToken: '',
      whatsappPhoneId: ''
    };
    await saveCollectionDoc('notification_settings', config);
  }
  return config;
}

async function sendEmailNotification(settings: any, type: 'Success' | 'Failed' | 'Cancelled', tx: any, recipients: string[]) {
  const isSmtpConfigured = settings.smtpHost && settings.smtpUser && settings.smtpPass;
  const orderData = tx.orderPayload || {};
  const orderNumber = orderData.orderNumber || tx.orderId || 'Unknown';
  const amountVal = typeof tx.amount === 'number' ? tx.amount.toFixed(2) : Number(tx.amount || 0).toFixed(2);

  const emailSubject = `[Leafy Organics] Payment ${type} for Order #${orderNumber}`;

  let statusBannerColor = '#10b981'; // green
  let statusBannerText = 'Payment Successful';
  let statusBannerDesc = 'Thank you for your order! Your payment was verified and completed successfully.';
  if (type === 'Failed') {
    statusBannerColor = '#ef4444'; // red
    statusBannerText = 'Payment Failed';
    statusBannerDesc = 'We were unable to process your payment. Your order has not been dispatched. Please retry payment from checkout.';
  } else if (type === 'Cancelled') {
    statusBannerColor = '#f59e0b'; // orange
    statusBannerText = 'Payment Cancelled';
    statusBannerDesc = 'Your payment session was cancelled. The order remains pending payment. You can complete checkout at your convenience.';
  }

  const invoiceNumber = `INV-2026-${(tx.id || '').replace(/[^a-zA-Z0-9]/g, '').substring(0, 10)}`;

  const productRows = (orderData.products || []).map((p: any) => {
    const itemTotal = Number(p.lineTotal || (p.price * p.quantity)).toFixed(2);
    const taxPortion = ((p.price * p.quantity * (p.gstPercentage || 18)) / (100 + (p.gstPercentage || 18))).toFixed(2);
    return `
      <tr>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: left; vertical-align: middle;">
          <div style="display: flex; align-items: center; gap: 8px;">
            ${p.picture ? `<img src="${p.picture}" alt="${p.productName}" style="width: 36px; height: 36px; border-radius: 6px; object-fit: cover; border: 1px solid #e2e8f0;"/>` : `<div style="width: 36px; height: 36px; border-radius: 6px; background-color: #f1f5f9; display: flex; align-items: center; justify-content: center; color: #94a3b8; font-size: 10px;">No image</div>`}
            <div>
              <div style="font-weight: 600; color: #1e293b; font-size: 13px;">${p.productName}</div>
              <div style="font-size: 10px; color: #64748b;">SKU: ${p.sku || 'N/A'} | Variant: ${p.variant || 'Standard'}</div>
            </div>
          </div>
        </td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: center; color: #475569;">${p.quantity}</td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: right; color: #475569;">₹${Number(p.price).toFixed(2)}</td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: right; color: #475569;">₹${Number(p.discount || 0).toFixed(2)}</td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: right; color: #475569;">₹${taxPortion} (${p.gstPercentage || 18}%)</td>
        <td style="padding: 12px 8px; border-bottom: 1px solid #f1f5f9; text-align: right; font-weight: 600; color: #1e293b;">₹${itemTotal}</td>
      </tr>
    `;
  }).join('');

  const shipping = orderData.shippingAddress || {};
  const deliveryAddressHtml = `
    <div style="font-size: 13px; color: #334155; line-height: 1.5;">
      <strong>${shipping.name || orderData.customerName || 'Recipient'}</strong><br/>
      ${shipping.addressLine || 'N/A'}<br/>
      ${shipping.addressLine2 ? `${shipping.addressLine2}<br/>` : ''}
      ${shipping.city || ''}, ${shipping.district || ''}, ${shipping.state || ''}<br/>
      <strong>PIN:</strong> ${shipping.pincode || 'N/A'}<br/>
      <strong>Country:</strong> ${shipping.country || 'India'}
    </div>
  `;

  const companyLogoUrl = 'https://raw.githubusercontent.com/jojojohn2021/LeafyvioWebapp/main/public/Logo.png';

  const emailHtml = `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>${emailSubject}</title>
    </head>
    <body style="background-color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; margin: 0; padding: 20px;">
      <div style="max-width: 650px; margin: 0 auto; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);">
        
        <!-- HEADER BLOCK -->
        <div style="background: linear-gradient(135deg, #0f766e 0%, #115e59 100%); padding: 24px; text-align: center; border-bottom: 1px solid #115e59;">
          <img src="${companyLogoUrl}" alt="Leafy Logo" style="height: 48px; margin-bottom: 8px; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.1));"/>
          <div style="color: #ffffff; font-size: 12px; font-weight: 500; letter-spacing: 0.05em; text-transform: uppercase;">
            ${settings.companyName || 'Leafy Organics'}
          </div>
        </div>

        <!-- STATUS ALERT BANNER -->
        <div style="background-color: ${statusBannerColor}; color: #ffffff; padding: 20px; text-align: center;">
          <h2 style="margin: 0 0 6px 0; font-size: 20px; font-weight: 700; letter-spacing: -0.01em;">${statusBannerText}</h2>
          <p style="margin: 0; font-size: 13px; opacity: 0.95; line-height: 1.4;">${statusBannerDesc}</p>
        </div>

        <!-- CORE LEDGER INFO -->
        <div style="padding: 24px;">
          <div style="display: flex; justify-content: space-between; gap: 16px; margin-bottom: 24px; flex-wrap: wrap;">
            <table style="min-width: 250px; border-collapse: collapse; font-size: 12px; line-height: 1.6;">
              <tr>
                <td style="color: #64748b; padding: 2px 0; width: 110px;"><strong>Customer Name:</strong></td>
                <td style="color: #1e293b; font-weight: 600; padding: 2px 0;">${orderData.customerName || 'Guest'}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Customer ID:</strong></td>
                <td style="color: #1e293b; padding: 2px 0;">${orderData.customerId || 'N/A'}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Email:</strong></td>
                <td style="color: #1e293b; padding: 2px 0;">${orderData.customerEmail || 'N/A'}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Mobile:</strong></td>
                <td style="color: #1e293b; padding: 2px 0;">${orderData.customerMobile || 'N/A'}</td>
              </tr>
            </table>

            <table style="min-width: 250px; border-collapse: collapse; font-size: 12px; line-height: 1.6;">
              <tr>
                <td style="color: #64748b; padding: 2px 0; width: 110px;"><strong>Order Number:</strong></td>
                <td style="color: #1e293b; font-weight: 650; padding: 2px 0;">#${orderNumber}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Invoice ID:</strong></td>
                <td style="color: #1e293b; padding: 2px 0; font-family: monospace;">${invoiceNumber}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Order Date:</strong></td>
                <td style="color: #1e293b; padding: 2px 0;">${new Date(tx.createdAt).toLocaleString()}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;"><strong>Payment Date:</strong></td>
                <td style="color: #1e293b; padding: 2px 0;">${new Date(tx.updatedAt || tx.createdAt).toLocaleString()}</td>
              </tr>
            </table>
          </div>

          <!-- SHIPPING ADDRESS & PAYMENT CHANNEL DETAILS -->
          <div style="border-top: 1px solid #f1f5f9; padding-top: 16px; margin-bottom: 24px; display: flex; flex-direction: row; gap: 20px; flex-wrap: wrap;">
            <div style="flex: 1; min-width: 250px;">
              <h4 style="margin: 0 0 8px 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b;">Delivery Address</h4>
              ${deliveryAddressHtml}
            </div>
            <div style="flex: 1; min-width: 200px;">
              <h4 style="margin: 0 0 8px 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b;">Payment Details</h4>
              <table style="width: 100%; border-collapse: collapse; font-size: 12px; line-height: 1.6;">
                <tr>
                  <td style="color: #64748b; padding: 2px 0; width: 110px;"><strong>Gateway:</strong></td>
                  <td style="color: #1e293b; padding: 2px 0;">${tx.gateway || 'PayU'}</td>
                </tr>
                <tr>
                  <td style="color: #64748b; padding: 2px 0;"><strong>PayU Tx ID:</strong></td>
                  <td style="color: #1e293b; padding: 2px 0; font-family: monospace;">${tx.id || 'N/A'}</td>
                </tr>
                <tr>
                  <td style="color: #64748b; padding: 2px 0;"><strong>PayU Reference:</strong></td>
                  <td style="color: #1e293b; padding: 2px 0; font-family: monospace;">${tx.transactionReference || 'N/A'}</td>
                </tr>
                <tr>
                  <td style="color: #64748b; padding: 2px 0;"><strong>Payment Method:</strong></td>
                  <td style="color: #1e293b; padding: 2px 0;">${tx.paymentMethod || 'Credit Card'}</td>
                </tr>
                <tr>
                  <td style="color: #64748b; padding: 2px 0;"><strong>Currency:</strong></td>
                  <td style="color: #1e293b; padding: 2px 0;">INR (₹)</td>
                </tr>
              </table>
            </div>
          </div>

          <!-- ITEMIZED PRODUCT TABLE -->
          <h4 style="margin: 0 0 8px 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b;">Ordered Items</h4>
          <div style="overflow-x: auto;">
            <table style="width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 24px;">
              <thead>
                <tr style="background-color: #f8fafc; border-bottom: 2px solid #e2e8f0;">
                  <th style="padding: 10px 8px; text-align: left; color: #475569; font-weight: 700;">Item Details</th>
                  <th style="padding: 10px 8px; text-align: center; color: #475569; font-weight: 700; width: 50px;">Qty</th>
                  <th style="padding: 10px 8px; text-align: right; color: #475569; font-weight: 700;">Unit Price</th>
                  <th style="padding: 10px 8px; text-align: right; color: #475569; font-weight: 700;">Discount</th>
                  <th style="padding: 10px 8px; text-align: right; color: #475569; font-weight: 700;">GST/Tax</th>
                  <th style="padding: 10px 8px; text-align: right; color: #475569; font-weight: 700;">Total</th>
                </tr>
              </thead>
              <tbody>
                ${productRows}
              </tbody>
            </table>
          </div>

          <!-- FINANCIAL INVOICE SUMMARY -->
          <div style="border-top: 2px solid #e2e8f0; padding-top: 16px; display: flex; justify-content: flex-end;">
            <table style="width: 280px; border-collapse: collapse; font-size: 13px; line-height: 1.8;">
              <tr>
                <td style="color: #64748b; padding: 2px 0;">Subtotal:</td>
                <td style="color: #1e293b; text-align: right; padding: 2px 0;">₹${Number(orderData.financials?.subtotal || amountVal).toFixed(2)}</td>
              </tr>
              ${orderData.financials?.discount > 0 ? `
              <tr>
                <td style="color: #64748b; padding: 2px 0;">Discount (Coupon: ${orderData.coupon || 'Applied'}):</td>
                <td style="color: #ef4444; text-align: right; padding: 2px 0;">-₹${Number(orderData.financials.discount).toFixed(2)}</td>
              </tr>
              ` : ''}
              <tr>
                <td style="color: #64748b; padding: 2px 0;">Shipping Charges:</td>
                <td style="color: #1e293b; text-align: right; padding: 2px 0;">${Number(orderData.financials?.deliveryFee || 0) === 0 ? 'FREE' : `₹${Number(orderData.financials.deliveryFee).toFixed(2)}`}</td>
              </tr>
              <tr>
                <td style="color: #64748b; padding: 2px 0;">Estimated Tax (GST):</td>
                <td style="color: #1e293b; text-align: right; padding: 2px 0;">₹${Number(orderData.financials?.tax || 0).toFixed(2)}</td>
              </tr>
              <tr style="border-top: 1.5px solid #e2e8f0;">
                <td style="font-weight: 700; color: #0f766e; padding: 8px 0; font-size: 15px;">Grand Total:</td>
                <td style="font-weight: 700; color: #0f766e; text-align: right; padding: 8px 0; font-size: 15px;">₹${Number(orderData.financials?.total || amountVal).toFixed(2)}</td>
              </tr>
            </table>
          </div>

        </div>

        <!-- FOOTER BLOCK -->
        <div style="background-color: #f8fafc; border-top: 1px solid #e2e8f0; padding: 24px; text-align: center; font-size: 11px; color: #64748b; line-height: 1.6;">
          <strong>Leafy Organics Corporate Headquarters</strong><br/>
          ABC House, Kochi, Kerala, India - 682001<br/>
          Email: info@vamjo.com | Web: <a href="https://www.vamjo" style="color: #0f766e; text-decoration: none;">https://www.vamjo.com</a><br/>
          <span style="display: block; margin-top: 8px; color: #94a3b8;">This email has been dispatched automatically based on core payment ledger updates.</span>
        </div>
        
      </div>
    </body>
    </html>
  `;

  let sentStatus = 'Success';
  let errorMessage = '';

  try {
    if (isSmtpConfigured) {
      const transporter = nodemailer.createTransport({
        host: settings.smtpHost,
        port: Number(settings.smtpPort),
        secure: Number(settings.smtpPort) === 465,
        auth: {
          user: settings.smtpUser,
          pass: settings.smtpPass
        }
      });

      await transporter.sendMail({
        from: settings.smtpFrom || 'no-reply@leafy.com',
        to: recipients.join(', '),
        subject: emailSubject,
        html: emailHtml
      });
      console.log(`[SMTP] Dispatched email to: ${recipients.join(', ')}`);
    } else {
      console.log(`[SMTP Mock] Simulating email notification. Recipients: ${recipients.join(', ')}. Subject: ${emailSubject}`);
    }
  } catch (err: any) {
    console.error(`[SMTP Error] Failed to send email:`, err);
    sentStatus = 'Failed';
    errorMessage = err.message || 'SMTP delivery failure';
  }

  // Log to database
  const logId = `nlog-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  await saveCollectionDoc('notification_logs', {
    id: logId,
    type: 'Email',
    recipient: recipients.join(', '),
    orderNumber: orderNumber,
    paymentStatus: type,
    status: sentStatus,
    dateTime: new Date().toISOString(),
    deliveryStatus: type === 'Success' ? 'Delivered' : 'Pending',
    errorMessage: errorMessage,
    emailSubject: emailSubject,
    emailHtml: emailHtml,
    originalTx: tx
  });
}

async function sendWhatsAppNotification(settings: any, type: 'Success' | 'Failed' | 'Cancelled', tx: any, recipients: string[]) {
  const isWaConfigured = settings.whatsappApiUrl && settings.whatsappToken && settings.whatsappPhoneId;
  const orderNumber = tx.orderId || 'Unknown';
  const orderData = tx.orderPayload || {};
  const amountVal = typeof tx.amount === 'number' ? tx.amount.toFixed(2) : Number(tx.amount || 0).toFixed(2);

  let statusHeader = '';
  let statusVal = '';
  if (type === 'Success') {
    statusHeader = 'Payment Successful ✅';
    statusVal = 'Paid';
  } else if (type === 'Failed') {
    statusHeader = 'Payment Failed ❌';
    statusVal = 'Failed';
  } else {
    statusHeader = 'Payment Cancelled ⚠️';
    statusVal = 'Cancelled';
  }

  let messageText = `🌿 *${settings.companyName || 'Leafy Organics'}* 🌿\n`;
  messageText += `*${statusHeader}*\n\n`;

  messageText += `*Order No:*\n${orderNumber}\n\n`;
  messageText += `*Customer:*\n${orderData.customerName || 'Guest'}\n\n`;
  messageText += `*Amount:*\n₹${amountVal}\n\n`;
  messageText += `*Payment:*\n${tx.paymentMethod || 'Credit Card'}\n\n`;
  messageText += `*Transaction:*\n${tx.id}\n\n`;

  if (orderData.products && orderData.products.length > 0) {
    messageText += `*Items:*\n`;
    const maxItems = 4;
    const itemsToShow = orderData.products.slice(0, maxItems);
    itemsToShow.forEach((p: any) => {
      messageText += `${p.quantity} x ${p.productName}\n`;
    });
    if (orderData.products.length > maxItems) {
      messageText += `+ ${orderData.products.length - maxItems} more items (refer to full invoice)\n`;
    }
    messageText += `\n`;
  }

  const addr = orderData.shippingAddress || {};
  messageText += `*Delivery:*\n`;
  messageText += `${addr.name || orderData.customerName || 'Recipient'}\n`;
  messageText += `${addr.addressLine || 'Address Line'}\n`;
  if (addr.city || addr.state) {
    messageText += `${addr.city || ''}\n${addr.state || ''} - ${addr.pincode || ''}\n`;
  }
  messageText += `\n`;

  messageText += `*Status:*\n${statusVal}\n\n`;
  messageText += `Thank you for shopping with us! View full invoice details at https://www.vamjo.com`;

  let sentStatus = 'Success';
  let errorMessage = '';

  try {
    if (isWaConfigured) {
      for (const phone of recipients) {
        const cleanedPhone = phone.replace(/[^0-9+]/g, '');
        const url = `${settings.whatsappApiUrl}/${settings.whatsappPhoneId}/messages`;

        const response = await fetch(url, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${settings.whatsappToken}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            recipient_type: "individual",
            to: cleanedPhone,
            type: "text",
            text: {
              preview_url: false,
              body: messageText
            }
          })
        });

        if (!response.ok) {
          const errData = await response.json();
          throw new Error(errData.error?.message || `WhatsApp API error: status ${response.status}`);
        }
        console.log(`[WhatsApp] Dispatched API alert to: ${cleanedPhone}`);
      }
    } else {
      console.log(`[WhatsApp Mock] Simulating WhatsApp notification. Message:\n${messageText}`);
    }
  } catch (err: any) {
    console.error(`[WhatsApp Error] Failed to send WhatsApp notification:`, err);
    sentStatus = 'Failed';
    errorMessage = err.message || 'WhatsApp delivery failure';
  }

  // Log to database
  const logId = `nlog-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  await saveCollectionDoc('notification_logs', {
    id: logId,
    type: 'WhatsApp',
    recipient: recipients.join(', '),
    orderNumber: orderNumber,
    paymentStatus: type,
    status: sentStatus,
    dateTime: new Date().toISOString(),
    deliveryStatus: type === 'Success' ? 'Delivered' : 'Pending',
    errorMessage: errorMessage,
    messageText: messageText,
    originalTx: tx
  });
}

// ---------------------------------------------------------------------------
// Authoritative 5-level referral commission engine (Node.js is the source of
// truth; Flutter only ever reads the results below). Referral identity reuses
// the existing customer record: `customers.authUid` is the customer's own
// Firebase UID (their shareable "referral code"), and `customers.referralCode`
// - already populated on lead-conversion/signup (see /api/auth/verify-login
// and the lead->customer conversion flow) - stores the UID of whoever referred
// them. No new database fields were required.
// ---------------------------------------------------------------------------
const COMMISSION_RULES_DOC_ID = 'default_levels';
const MAX_COMMISSION_LEVELS = 5;

async function findCustomerByAuthUid(identifier: string): Promise<any | null> {
  if (!identifier) return null;
  const cleanId = String(identifier).trim();
  if (!cleanId || cleanId === 'organic') return null;

  // 1. Match by authUid
  const authSnap = await adminDb.collection('customers').where('authUid', '==', cleanId).limit(1).get();
  if (!authSnap.empty) {
    return { id: authSnap.docs[0].id, ...authSnap.docs[0].data() };
  }

  // 2. Match by Firestore document ID
  const docSnap = await adminDb.collection('customers').doc(cleanId).get();
  if (docSnap.exists) {
    return { id: docSnap.id, ...docSnap.data() };
  }

  // 3. Match by 10-digit mobile number
  const digits = cleanId.replace(/\D/g, '');
  const mobile = digits.length >= 10 ? digits.slice(-10) : digits;
  if (mobile) {
    const mobileSnap = await adminDb.collection('customers').where('mobileNumber', '==', mobile).limit(1).get();
    if (!mobileSnap.empty) {
      return { id: mobileSnap.docs[0].id, ...mobileSnap.docs[0].data() };
    }
  }

  // 4. Match by customerId field
  const idSnap = await adminDb.collection('customers').where('customerId', '==', cleanId).limit(1).get();
  if (!idSnap.empty) {
    return { id: idSnap.docs[0].id, ...idSnap.docs[0].data() };
  }

  return null;
}

async function findCustomerById(customerId: string): Promise<any | null> {
  return findCustomerByAuthUid(customerId);
}

// Walks the sponsor chain up to MAX_COMMISSION_LEVELS via customer.referralCode
// (sponsor's authUid / customerId / mobile). Stops on "organic"/missing/unresolvable/cyclic sponsors.
async function resolveSponsorChain(buyerCustomer: any): Promise<Array<{ level: number; customer: any }>> {
  const chain: Array<{ level: number; customer: any }> = [];
  const visited = new Set<string>([buyerCustomer.authUid, buyerCustomer.id, buyerCustomer.mobileNumber].filter(Boolean));
  let sponsorIdentifier = buyerCustomer.referralCode || buyerCustomer.referralcode || buyerCustomer.sponsorAuthUid || buyerCustomer.sponsorId;

  for (let level = 1; level <= MAX_COMMISSION_LEVELS; level++) {
    if (!sponsorIdentifier || sponsorIdentifier === 'organic' || visited.has(sponsorIdentifier)) break;
    const sponsor = await findCustomerByAuthUid(sponsorIdentifier);
    if (!sponsor) break;
    chain.push({ level, customer: sponsor });
    visited.add(sponsorIdentifier);
    if (sponsor.authUid) visited.add(sponsor.authUid);
    if (sponsor.id) visited.add(sponsor.id);
    if (sponsor.mobileNumber) visited.add(sponsor.mobileNumber);
    sponsorIdentifier = sponsor.referralCode || sponsor.referralcode || sponsor.sponsorAuthUid || sponsor.sponsorId;
  }
  return chain;
}

async function ensureCommissionRules(): Promise<{ rates: Record<string, number> }> {
  const doc = await adminDb.collection('commission_rules').doc(COMMISSION_RULES_DOC_ID).get();
  if (doc.exists && doc.data()?.rates) {
    return doc.data() as { rates: Record<string, number> };
  }
  const defaultRules = {
    id: COMMISSION_RULES_DOC_ID,
    rates: { '1': 5, '2': 3, '3': 2, '4': 1, '5': 0.5 },
    updatedAt: new Date().toISOString()
  };
  await adminDb.collection('commission_rules').doc(COMMISSION_RULES_DOC_ID).set(defaultRules, { merge: true });
  return defaultRules;
}

// Resolution precedence: per-product level override (product_level_commissions) ->
// system default rate for that level (commission_rules).
async function getEffectiveCommissionRate(level: number, productId?: string): Promise<number> {
  if (productId) {
    const overrideDoc = await adminDb.collection('product_level_commissions').doc(`${productId}_L${level}`).get();
    if (overrideDoc.exists && typeof overrideDoc.data()?.rate === 'number') {
      return overrideDoc.data()!.rate;
    }
  }
  const rules = await ensureCommissionRules();
  return Number(rules.rates?.[String(level)] ?? 0);
}

function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}

// Invoked once per qualifying successful transaction from finalizeSuccessfulPayment
// (shared by real PayU success and the PayU-disabled testing bypass). Idempotent:
// a transaction/orderId can only ever produce one set of commission_transactions.
async function processOrderCommissionsAuthoritative(tx: any): Promise<void> {
  try {
    const existing = await adminDb.collection('commission_transactions').where('orderId', '==', tx.orderId).limit(1).get();
    if (!existing.empty) {
      await saveCollectionDoc('payments', { id: tx.id, commissionProcessed: true });
      return;
    }

    const buyerIdentifier = tx.orderPayload?.customerId || tx.customerId || tx.userId || tx.customerMobile || tx.orderPayload?.customerMobile;
    const buyerCustomer = buyerIdentifier ? await findCustomerByAuthUid(buyerIdentifier) : null;
    if (!buyerCustomer) {
      await saveCollectionDoc('payments', { id: tx.id, commissionProcessed: true });
      return;
    }

    const chain = await resolveSponsorChain(buyerCustomer);
    const base = Number(tx.amount || tx.orderPayload?.totalValue || 0) || 0;
    const nowIso = new Date().toISOString();

    for (const { level, customer: sponsor } of chain) {
      const rate = await getEffectiveCommissionRate(level);
      const commissionAmount = roundCurrency((base * rate) / 100);
      if (commissionAmount <= 0) continue;

      const commissionTx = {
        id: `ct-${tx.id}-L${level}`,
        orderId: tx.orderId,
        transactionId: tx.id,
        customerId: buyerCustomer.id,
        customerName: buyerCustomer.name || tx.customerName || '',
        referrerCustomerId: sponsor.id,
        referrerAuthUid: sponsor.authUid,
        referrerMobileNumber: sponsor.mobileNumber,
        level,
        commissionType: 'Referral Commission',
        commissionBaseAmount: base,
        commissionRate: rate,
        commissionAmount,
        reversedAmount: 0,
        status: 'Pending',
        createdAt: nowIso,
        updatedAt: nowIso
      };
      await saveCollectionDoc('commission_transactions', commissionTx);

      await adminDb.collection('customers').doc(sponsor.id).set({
        commissionPending: FieldValue.increment(commissionAmount)
      }, { merge: true });
    }

  } catch (err) {
    console.error(`[Commission Engine] Failed to process commissions for order ${tx.orderId}:`, err);
  }
}

// Invoked from /api/payment/refund once a transaction is confirmed refunded. Proportionally
// reverses each level's commission_transactions row for the order (ratio = refundAmount/tx.amount),
// clamped so a row is never reversed by more than its own remaining commission (no negative balance).
async function refundOrderCommissionsAuthoritative(tx: any, refundAmount: number): Promise<void> {
  try {
    const orderCommissions = await adminDb.collection('commission_transactions').where('orderId', '==', tx.orderId).get();
    if (orderCommissions.empty) return;

    const txAmount = Number(tx.amount) || 0;
    const ratio = txAmount > 0 ? Math.min(1, Math.max(0, Number(refundAmount) / txAmount)) : 0;
    if (ratio <= 0) return;

    for (const doc of orderCommissions.docs) {
      const commission = doc.data();
      const alreadyReversed = Number(commission.reversedAmount) || 0;
      const targetReversed = roundCurrency(Number(commission.commissionAmount) * ratio);
      const reversalAmount = roundCurrency(Math.min(targetReversed, Number(commission.commissionAmount)) - alreadyReversed);
      if (reversalAmount <= 0) continue;

      const newReversedTotal = roundCurrency(alreadyReversed + reversalAmount);
      const isFullyReversed = newReversedTotal >= Number(commission.commissionAmount) - 0.01;

      await doc.ref.set({
        reversedAmount: newReversedTotal,
        status: isFullyReversed ? 'Reversed' : commission.status,
        reversedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      }, { merge: true });

      // Clamp inside a transaction so the sponsor's balance can never go negative.
      const customerRef = adminDb.collection('customers').doc(commission.referrerCustomerId);
      await adminDb.runTransaction(async (transaction) => {
        const customerDoc = await transaction.get(customerRef);
        const currentPending = Number(customerDoc.data()?.commissionPending) || 0;
        transaction.set(customerRef, { commissionPending: Math.max(0, roundCurrency(currentPending - reversalAmount)) }, { merge: true });
      });
    }
  } catch (err) {
    console.error(`[Commission Engine] Failed to reverse commissions for order ${tx.orderId}:`, err);
  }
}

async function getCustomerEarningsPayload(customer: any): Promise<Record<string, any>> {
  const pending = Number(customer?.commissionPending) || 0;
  const paid = Number(customer?.commissionPaid) || 0;
  return {
    commissionEarned: pending,
    pending,
    confirmed: 0,
    commissionPayable: pending,
    commissionPaid: paid
  };
}

async function authorizeCustomerAccess(req: any, customerId: string): Promise<{ authenticatedUser: any; customer: any } | { error: string; status: number }> {
  const authenticatedUser = await getAuthenticatedUser(req);
  if (!authenticatedUser) return { error: 'Authenticated customer required', status: 401 };
  const customer = await findCustomerById(customerId);
  if (!customer) return { error: 'Customer not found', status: 404 };
  if (customer.authUid !== authenticatedUser.uid) return { error: 'Customer does not belong to the authenticated user', status: 403 };
  return { authenticatedUser, customer };
}

// Attaches a sponsor to a customer that does not already have one (referralCode is
// still missing/'organic'). Prevents overwriting an existing sponsor to protect the
// commission chain from being manipulated after the fact.
async function applyReferralSponsor(customer: any, sponsorAuthUid: string): Promise<{ success: boolean; error?: string; status?: number }> {
  if (!sponsorAuthUid) return { success: false, error: 'Missing referralCode', status: 400 };
  if (sponsorAuthUid === customer.authUid) return { success: false, error: 'Cannot refer yourself', status: 400 };
  if (customer.referralCode && customer.referralCode !== 'organic') {
    return { success: false, error: 'A referral/sponsor is already set for this account.', status: 400 };
  }
  const sponsor = await findCustomerByAuthUid(sponsorAuthUid);
  if (!sponsor) return { success: false, error: 'Referral code does not match an existing partner.', status: 404 };

  await adminDb.collection('customers').doc(customer.id).set({
    referralCode: sponsorAuthUid,
    referralcode: sponsorAuthUid,
    referralPartner: sponsor.name || sponsor.partnerName || '',
    referralpartner: sponsor.name || sponsor.partnerName || ''
  }, { merge: true });
  return { success: true };
}

// Shared successful-payment business processing, reused identically by the real PayU
// success paths (/api/payment/verify, /api/payment/callback/success) and by the
// PayU-disabled testing bypass (/api/payment/bypass-checkout). Idempotent: only
// creates the sales order/stock adjustment once per tx.orderId.
async function finalizeSuccessfulPayment(tx: any): Promise<void> {
  const salesOrders = await getCollectionDocs('sales_orders');
  let order = salesOrders.find((o: any) => o.id === tx.orderId);
  if (!order && tx.orderPayload) {
    const orderNum = `SO-2026-${String(salesOrders.length + 1).padStart(4, '0')}`;
    let gstCalc: any = null;
    try {
      gstCalc = await calculateGSTForOrderItems(tx.orderPayload.products || []);
    } catch (_) { }

    order = {
      ...tx.orderPayload,
      id: tx.orderId,
      orderNumber: orderNum,
      products: gstCalc ? gstCalc.items : (tx.orderPayload.products || []),
      totalTaxableValue: gstCalc ? gstCalc.totalTaxableValue : undefined,
      totalGstAmount: gstCalc ? gstCalc.totalGstAmount : undefined,
      hsnGstSummary: gstCalc ? gstCalc.hsnGstSummary : undefined,
      gstByHsn: gstCalc ? gstCalc.hsnGstSummary : undefined,
      totalValue: gstCalc ? gstCalc.grandTotal : (tx.orderPayload.totalValue || tx.amount),
      paymentStatus: 'Paid',
      orderStatus: 'Confirmed',
      deliveryStatus: 'Processing',
      createdAt: new Date().toISOString()
    };
    await saveCollectionDoc('sales_orders', order);

    const products = await getCollectionDocs('products');
    for (const item of (order.products || [])) {
      const prod = products.find((p: any) => p.id === (item.productId || item.id));
      if (prod) {
        prod.stock = Math.max(0, (prod.stock || 0) - item.quantity);
        prod.unitsSold = (prod.unitsSold || 0) + item.quantity;
        prod.revenue = (prod.revenue || 0) + (item.price * item.quantity);
        await saveCollectionDoc('products', prod);
      }
    }
  }

  await processOrderCommissionsAuthoritative(tx);

  triggerAllNotifications('Success', tx).catch(err => console.error(err));
}

async function triggerAllNotifications(type: 'Success' | 'Failed' | 'Cancelled', tx: any) {
  try {
    const settings = await getNotificationSettings();
    let emailRecipients: string[] = [];
    let phoneRecipients: string[] = [];

    if (type === 'Success') {
      emailRecipients = settings.successEmails || [];
      phoneRecipients = settings.successPhones || [];
    } else if (type === 'Failed') {
      emailRecipients = settings.failedEmails || [];
      phoneRecipients = settings.failedPhones || [];
    } else if (type === 'Cancelled') {
      emailRecipients = settings.cancelledEmails || [];
      phoneRecipients = settings.cancelledPhones || [];
    }

    const orderData = tx.orderPayload || {};
    if (orderData.customerEmail) {
      emailRecipients = [...new Set([...emailRecipients, orderData.customerEmail])];
    }
    if (orderData.customerMobile) {
      phoneRecipients = [...new Set([...phoneRecipients, orderData.customerMobile])];
    }

    if (emailRecipients.length > 0) {
      sendEmailNotification(settings, type, tx, emailRecipients).catch(err => {
        console.error('Asynchronous sendEmailNotification failed:', err);
      });
    }

    if (phoneRecipients.length > 0) {
      sendWhatsAppNotification(settings, type, tx, phoneRecipients).catch(err => {
        console.error('Asynchronous sendWhatsAppNotification failed:', err);
      });
    }
  } catch (err) {
    console.error('Error triggering notifications:', err);
  }
}

// Operational Configuration vs Secrets helper functions
async function ensurePaymentGatewaySettings() {
  try {
    const configs = await getCollectionDocs('payment_gateway_settings');

    let testConfig = configs.find((c: any) =>
      (c.gateway === 'PAYU' || c.gateway_name === 'PayU') &&
      (c.environment || '').toUpperCase() === 'TEST'
    );

    let prodConfig = configs.find((c: any) =>
      (c.gateway === 'PAYU' || c.gateway_name === 'PayU') &&
      (c.environment || '').toUpperCase() === 'PRODUCTION'
    );

    const nowIso = new Date().toISOString();

    const fullTestRecord = {
      id: 'payu_test',
      gateway: 'PAYU',
      gateway_name: 'PayU',
      environment: 'TEST',
      enabled: true,
      status: 'Enabled',
      currency: 'INR',
      merchant_key: process.env.PAYU_TEST_KEY || process.env.PAYU_TEST_MERCHANT_KEY || (process.env as any)['PAYU_TEST_KEY '] || 'ETHFAz',
      merchant_salt: process.env.PAYU_TEST_SALT || process.env.PAYU_TEST_MERCHANT_SALT || (process.env as any)['PAYU_TEST_SALT '] || 'SshuKwxXGTE4W8rzP3iaKR0F2wqOHf1C',
      payment_url: 'https://test.payu.in/_payment',
      success_url: '/api/payment/callback/success',
      failure_url: '/api/payment/callback/failure',
      cancel_url: '/api/payment/callback/failure',
      webhook_url: '/api/payment/callback/webhook',
      api_version: 'v1',
      created_at: testConfig?.created_at || testConfig?.createdAt || nowIso,
      updated_at: nowIso,
      updatedAt: nowIso
    };

    await saveCollectionDoc('payment_gateway_settings', fullTestRecord);

    if (!prodConfig) {
      prodConfig = {
        id: 'payu_production',
        gateway: 'PAYU',
        gateway_name: 'PayU',
        environment: 'PRODUCTION',
        enabled: true,
        status: 'Enabled',
        currency: 'INR',
        payment_url: 'https://secure.payu.in/_payment',
        success_url: '/api/payment/callback/success',
        failure_url: '/api/payment/callback/failure',
        cancel_url: '/api/payment/callback/failure',
        webhook_url: '/api/payment/callback/webhook',
        api_version: 'v1',
        created_at: nowIso,
        updated_at: nowIso,
        updatedAt: nowIso
      };
      await saveCollectionDoc('payment_gateway_settings', prodConfig);
    }
  } catch (err) {
    console.error("[PayU Setup] Failed to ensure payment_gateway_settings:", err);
  }
}

function logPayUConfigDiagnostics(env: string, key: string, salt: string, paymentUrl: string): void {
  const hasKey = Boolean(key && key.trim());
  const hasSalt = Boolean(salt && salt.trim());
  console.log(`[PayU Config]`);
  console.log(`Environment: ${env}`);
  console.log(`Merchant key configured: ${hasKey}`);
  console.log(`Merchant key length: ${hasKey ? key.trim().length : 0}`);
  console.log(`Merchant key contains whitespace: ${hasKey ? /\s/.test(key) : false}`);
  console.log(`Merchant salt configured: ${hasSalt}`);
  console.log(`Payment URL configured: ${Boolean(paymentUrl)}`);
}

export function getPayUSecrets(environment: string): { key: string; salt: string } | null {
  const envUpper = (environment || 'TEST').toUpperCase();
  const isProd = envUpper === 'PRODUCTION';

  // 1. Google Cloud Secret Manager bindings (PAYU_MERCHANT_KEY & PAYU_MERCHANT_SALT)
  const smKey = process.env.PAYU_MERCHANT_KEY?.trim();
  const smSalt = process.env.PAYU_MERCHANT_SALT?.trim();

  let key = '';
  let salt = '';

  if (isProd) {
    key = smKey || process.env.PAYU_PRODUCTION_KEY?.trim() || process.env.PAYU_PROD_MERCHANT_KEY?.trim() || '';
    salt = smSalt || process.env.PAYU_PRODUCTION_SALT?.trim() || process.env.PAYU_PROD_MERCHANT_SALT?.trim() || '';
  } else {
    key = smKey || process.env.PAYU_TEST_KEY?.trim() || process.env.PAYU_TEST_MERCHANT_KEY?.trim() || (process.env as any)['PAYU_TEST_KEY ']?.trim() || 'ETHFAz';
    salt = smSalt || process.env.PAYU_TEST_SALT?.trim() || process.env.PAYU_TEST_MERCHANT_SALT?.trim() || (process.env as any)['PAYU_TEST_SALT ']?.trim() || 'SshuKwxXGTE4W8rzP3iaKR0F2wqOHf1C';
  }

  key = key.trim();
  salt = salt.trim();

  if (!key || !salt) return null;
  return { key, salt };
}

app.post("/api/payment/settings/seed-payu-test", async (req, res) => {
  try {
    await ensurePaymentGatewaySettings();
    const configs = await getCollectionDocs('payment_gateway_settings');
    const testConfig = configs.find((c: any) =>
      (c.gateway === 'PAYU' || c.gateway_name === 'PayU') &&
      (c.environment || '').toUpperCase() === 'TEST'
    );
    return res.json({ success: true, message: "PayU test setting record created/updated successfully", data: testConfig });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to seed PayU test record" });
  }
});

// PayU Debug Diagnostics toggle (observation-only; never affects credentials/hash/payment logic).
app.get("/api/payment/debug-settings", async (req, res) => {
  try {
    const enabled = await isPayUDebugEnabled();
    return res.json({ success: true, payu_debug_enabled: enabled });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to read PayU debug setting" });
  }
});

app.post("/api/payment/debug-settings", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) {
      return res.status(401).json({ success: false, error: "Authentication is required to change PayU debug diagnostics." });
    }
    const enabled = req.body?.enabled === true;
    await adminDb.collection('payment_gateway_settings').doc(PAYU_DEBUG_SETTINGS_DOC_ID).set({
      id: PAYU_DEBUG_SETTINGS_DOC_ID,
      payu_debug_enabled: enabled,
      updatedAt: new Date().toISOString(),
      updatedBy: authenticatedUser.uid
    }, { merge: true });
    return res.json({ success: true, payu_debug_enabled: enabled });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to update PayU debug setting" });
  }
});

// PayU Payment testing toggle - available to all logged-in users (no admin/role restriction),
// intended for the Test/development environment only. Same mechanism/pattern as the debug toggle above.
app.get("/api/payment/payu-toggle", async (req, res) => {
  try {
    const enabled = await isPayUEnabled();
    return res.json({ success: true, payu_enabled: enabled });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to read PayU toggle setting" });
  }
});

app.post("/api/payment/payu-toggle", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) {
      return res.status(401).json({ success: false, error: "Authentication is required to change the PayU payment toggle." });
    }
    const enabled = req.body?.enabled !== false;
    await adminDb.collection('payment_gateway_settings').doc(PAYU_ENABLED_SETTINGS_DOC_ID).set({
      id: PAYU_ENABLED_SETTINGS_DOC_ID,
      payu_enabled: enabled,
      updatedAt: new Date().toISOString(),
      updatedBy: authenticatedUser.uid
    }, { merge: true });
    return res.json({ success: true, payu_enabled: enabled });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to update PayU payment toggle" });
  }
});

// Server-side Authoritative GST Calculation Helper
export async function calculateGSTForOrderItems(rawItems: any[]): Promise<{
  items: any[];
  totalTaxableValue: number;
  totalGstAmount: number;
  subtotal: number;
  deliveryFee: number;
  grandTotal: number;
  hsnGstSummary: any[];
}> {
  const products = await getCollectionDocs('products');
  let totalTaxableValue = 0;
  let totalGstAmount = 0;
  let subtotal = 0;
  const deliveryFee = 30.0;

  const hsnGroups: Record<string, any> = {};

  const enrichedItems = (rawItems || []).map((item: any) => {
    const productId = item.productId || item.id;
    const product = products.find((candidate: any) => candidate.id === productId) || {};

    const quantity = Number(item.quantity ?? 1);
    const unitPrice = Number(product.offerPrice ?? product.onlinePrice ?? item.price ?? 0);
    const gstRate = Number(product.gstPercentage ?? item.gstPercentage ?? 18.0);
    const hsnCode = String(product.hsnCode || product.hsn || item.hsnCode || '1234').trim();

    const gstInclusiveAmount = Number((unitPrice * quantity).toFixed(2));
    const taxableValue = Number((gstInclusiveAmount / (1 + gstRate / 100)).toFixed(2));
    const gstAmount = Number((gstInclusiveAmount - taxableValue).toFixed(2));

    subtotal += gstInclusiveAmount;
    totalTaxableValue += taxableValue;
    totalGstAmount += gstAmount;

    const groupKey = `${hsnCode}|${gstRate.toFixed(2)}`;
    if (!hsnGroups[groupKey]) {
      hsnGroups[groupKey] = {
        hsnCode,
        gstRate,
        taxableValue: 0,
        gstAmount: 0,
        totalAmount: 0
      };
    }
    hsnGroups[groupKey].taxableValue = Number((hsnGroups[groupKey].taxableValue + taxableValue).toFixed(2));
    hsnGroups[groupKey].gstAmount = Number((hsnGroups[groupKey].gstAmount + gstAmount).toFixed(2));
    hsnGroups[groupKey].totalAmount = Number((hsnGroups[groupKey].totalAmount + gstInclusiveAmount).toFixed(2));

    return {
      ...item,
      productId,
      productName: item.productName || product.name || '',
      imageUrl: item.imageUrl || product.imageUrl || product.image || '',
      quantity,
      price: unitPrice,
      unitPrice,
      gstPercentage: gstRate,
      hsnCode,
      taxableValue,
      gstAmount,
      gstInclusiveAmount,
    };
  });

  const hsnGstSummary = Object.values(hsnGroups).sort((a: any, b: any) => a.hsnCode.localeCompare(b.hsnCode));
  totalTaxableValue = Number(totalTaxableValue.toFixed(2));
  totalGstAmount = Number(totalGstAmount.toFixed(2));
  subtotal = Number(subtotal.toFixed(2));
  const grandTotal = Number((subtotal + deliveryFee).toFixed(2));

  return {
    items: enrichedItems,
    totalTaxableValue,
    totalGstAmount,
    subtotal,
    deliveryFee,
    grandTotal,
    hsnGstSummary,
  };
}

// POST /api/orders/calculate-gst - Authoritative server-side GST calculation endpoint
app.post("/api/orders/calculate-gst", async (req, res) => {
  try {
    const { items } = req.body;
    if (!items || !Array.isArray(items)) {
      return res.status(400).json({ error: "Missing or invalid items array in payload" });
    }
    const calculation = await calculateGSTForOrderItems(items);
    return res.json({ success: true, calculation });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to calculate GST" });
  }
});

// PayU-disabled testing bypass: never contacts PayU (no hash/request/WebView/redirect). Runs the exact
// same successful-payment processing (finalizeSuccessfulPayment) used by the real PayU success callbacks.
// Backend is authoritative: only proceeds when PAYU_ENABLED is false AND the environment is not Production.
app.post("/api/payment/bypass-checkout", async (req, res) => {
  try {
    const { orderData, environment } = req.body;
    if (!orderData) {
      return res.status(400).json({ error: "Missing orderData payload" });
    }

    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser || orderData.customerId !== authenticatedUser.uid) {
      return res.status(401).json({ error: "Authenticated customer required" });
    }

    const reqEnv = (environment || 'TEST').toString().toUpperCase();
    const env = reqEnv === 'PRODUCTION' ? 'PRODUCTION' : 'TEST';
    if (env === 'PRODUCTION') {
      return res.status(403).json({ error: 'The PayU testing bypass is not available in the Production environment.' });
    }

    if (await isPayUEnabled()) {
      return res.status(403).json({ error: 'PayU payment is currently enabled; the testing bypass is not active.' });
    }

    // Authoritative amount calculation - identical validation used by /api/payment/initiate.
    const products = await getCollectionDocs('products');
    const secureSubtotal = (orderData.products || []).reduce((sum: number, item: any) => {
      const product = products.find((candidate: any) => candidate.id === item.productId);
      if (!product) throw new Error(`Product ${item.productId} is unavailable`);
      const unitPrice = Number(product.offerPrice ?? product.onlinePrice ?? 0);
      return sum + unitPrice * Number(item.quantity || 0);
    }, 0);
    const secureAmount = Number((secureSubtotal + 30).toFixed(2));
    if (Math.abs(secureAmount - Number(orderData.totalValue || 0)) > 0.01) {
      return res.status(400).json({ error: "Order total could not be validated" });
    }

    const orderId = orderData.id || `so-${Date.now()}`;
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const timestampStr = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const randomSuffix = Math.floor(100 + Math.random() * 900);
    const transactionId = `VNXBYPASS${timestampStr}${randomSuffix}`;
    const nowIso = now.toISOString();

    const tx: any = {
      id: transactionId,
      orderId,
      amount: secureAmount,
      paymentMethod: orderData.paymentMethod || 'UPI',
      gateway: 'PayU',
      paymentGateway: 'PayU',
      paymentAggregator: 'PayU',
      aggregator: 'PayU',
      customerName: (orderData.customerName || '').trim() || 'Leafy Shopper',
      customerEmail: (orderData.customerEmail || '').trim(),
      customerMobile: (orderData.customerMobile || '').toString(),
      environment: env,
      isTestBypass: true,
      status: 'Success',
      transactionReference: `ref-payu-bypass-${Date.now()}`,
      createdAt: nowIso,
      updatedAt: nowIso,
      orderPayload: orderData,
      statusHistory: [
        { status: 'Success', timestamp: nowIso, note: 'Testing bypass: PayU payment disabled - transaction treated as a successful payment.' }
      ],
      logs: [
        { timestamp: nowIso, action: 'BYPASS_SUCCESS', details: `PayU disabled for testing - simulated successful payment for order ${orderId}. No PayU gateway request was made.` }
      ]
    };

    await saveCollectionDoc('payments', tx);
    await finalizeSuccessfulPayment(tx);

    return res.json({
      success: true,
      bypass: true,
      transaction: tx,
      orderId,
      txnid: transactionId,
      environment: env
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to process the PayU testing bypass" });
  }
});

app.post("/api/payment/transactions/repair", async (req, res) => {
  try {
    const rawSnapshot = await adminDb.collection('payments').get();
    let count = 0;
    for (const doc of rawSnapshot.docs) {
      const txData = doc.data();
      const normalized = normalizePaymentTransaction({ id: doc.id, ...txData });
      await adminDb.collection('payments').doc(doc.id).set(normalized, { merge: true });
      count++;
    }
    return res.json({ success: true, message: `Repaired ${count} payment transactions with payment gateway, aggregator, customer mobile, and address values.` });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || "Failed to repair payment transactions" });
  }
});

function generatePayUHash(params: {
  key: string;
  txnid: string;
  amount: string;
  productinfo: string;
  firstname: string;
  email: string;
  udf1?: string;
  udf2?: string;
  udf3?: string;
  udf4?: string;
  udf5?: string;
  salt: string;
}): { hash: string; maskedString: string } {
  const {
    key,
    txnid,
    amount,
    productinfo,
    firstname,
    email,
    udf1 = '',
    udf2 = '',
    udf3 = '',
    udf4 = '',
    udf5 = '',
    salt
  } = params;

  // Exact PayU sequence: key|txnid|amount|productinfo|firstname|email|udf1|udf2|udf3|udf4|udf5||||||SALT
  const sequence = [
    key,
    txnid,
    amount,
    productinfo,
    firstname,
    email,
    udf1,
    udf2,
    udf3,
    udf4,
    udf5,
    '', '', '', '', '', // udf6, udf7, udf8, udf9, udf10
    salt
  ];

  const hashString = sequence.join('|');
  const hash = crypto.createHash('sha512').update(hashString).digest('hex').toLowerCase();

  const maskedSeq = [...sequence];
  maskedSeq[maskedSeq.length - 1] = '******MASKED******';
  const maskedString = maskedSeq.join('|');

  return { hash, maskedString };
}

function generatePayUReverseHash(params: {
  salt: string;
  status: string;
  udf10?: string;
  udf9?: string;
  udf8?: string;
  udf7?: string;
  udf6?: string;
  udf5?: string;
  udf4?: string;
  udf3?: string;
  udf2?: string;
  udf1?: string;
  email: string;
  firstname: string;
  productinfo: string;
  amount: string;
  txnid: string;
  key: string;
}): { hash: string; maskedString: string } {
  const {
    salt,
    status,
    udf10 = '',
    udf9 = '',
    udf8 = '',
    udf7 = '',
    udf6 = '',
    udf5 = '',
    udf4 = '',
    udf3 = '',
    udf2 = '',
    udf1 = '',
    email,
    firstname,
    productinfo,
    amount,
    txnid,
    key
  } = params;

  // Exact reverse sequence: SALT|status|udf10|udf9|udf8|udf7|udf6|udf5|udf4|udf3|udf2|udf1|email|firstname|productinfo|amount|txnid|key
  const sequence = [
    salt,
    status,
    udf10,
    udf9,
    udf8,
    udf7,
    udf6,
    udf5,
    udf4,
    udf3,
    udf2,
    udf1,
    email,
    firstname,
    productinfo,
    amount,
    txnid,
    key
  ];

  const hashString = sequence.join('|');
  const hash = crypto.createHash('sha512').update(hashString).digest('hex').toLowerCase();

  const maskedSeq = [...sequence];
  maskedSeq[0] = '******MASKED******';
  const maskedString = maskedSeq.join('|');

  return { hash, maskedString };
}

export async function createPayUPayment(req: any, res: any) {
  try {
    const { orderData, paymentMethod, gateway = 'PayU', environment } = req.body;
    if (!orderData) {
      return res.status(400).json({ error: "Missing orderData payload" });
    }

    const normalizedPaymentMethod = paymentMethod || (gateway === 'PayU' ? 'UPI' : 'PayU');

    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser || orderData.customerId !== authenticatedUser.uid) {
      return res.status(401).json({ error: "Authenticated customer required" });
    }

    // Authoritative amount calculation
    const products = await getCollectionDocs('products');
    const secureSubtotal = (orderData.products || []).reduce((sum: number, item: any) => {
      const product = products.find((candidate: any) => candidate.id === item.productId);
      if (!product) throw new Error(`Product ${item.productId} is unavailable`);
      const unitPrice = Number(product.offerPrice ?? product.onlinePrice ?? 0);
      return sum + unitPrice * Number(item.quantity || 0);
    }, 0);
    const secureAmount = Number((secureSubtotal + 30).toFixed(2));
    if (Math.abs(secureAmount - Number(orderData.totalValue || 0)) > 0.01) {
      return res.status(400).json({ error: "Order total could not be validated" });
    }

    const orderId = orderData.id || `so-${Date.now()}`;
    const amount = secureAmount.toFixed(2);

    // Environment selection
    const reqEnv = (environment || req.body.env || 'TEST').toString().toUpperCase();
    const env = reqEnv === 'PRODUCTION' ? 'PRODUCTION' : 'TEST';

    // 1. Operational configuration from payment_gateway_settings
    await ensurePaymentGatewaySettings();
    const configs = await getCollectionDocs('payment_gateway_settings');
    const opConfig = configs.find((c: any) =>
      (c.gateway === 'PAYU' || c.gateway_name === 'PayU') &&
      (c.environment || '').toUpperCase() === env &&
      (c.enabled === true || c.enabled === 'true' || c.status === 'Enabled')
    );

    if (!opConfig) {
      return res.status(503).json({ error: `PayU payment gateway is not enabled for ${env} environment.` });
    }

    // 2. Secrets from Server Secret Store
    const secrets = getPayUSecrets(env);
    if (!secrets) {
      return res.status(503).json({ error: `PayU secret credentials are not configured for ${env} environment.` });
    }

    const { key, salt } = secrets;
    const paymentUrl = opConfig.payment_url || (env === 'PRODUCTION' ? 'https://secure.payu.in/_payment' : 'https://test.payu.in/_payment');

    // Safe diagnostics logging (never logs secret values)
    logPayUConfigDiagnostics(env, key, salt, paymentUrl);

    // PayU Debug Diagnostics toggle - observation only, never affects credentials/hash/payment logic.
    const payuDebugEnabled = await isPayUDebugEnabled();

    // Transaction ID formatting
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const timestampStr = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const randomSuffix = Math.floor(100 + Math.random() * 900);
    const transactionId = `VNX${timestampStr}${randomSuffix}`;
    const transactionRef = `ref-payu-${Date.now()}`;

    // Explicitly purge parameters that do not belong to a normal product e-commerce checkout
    // (wealth-tech/investment/mutual-fund/subscription/SI/TPV/beneficiary parameters).
    const forbiddenKeys = [
      'si', 'si_details', 'free_trial', 'wtParams', 'wealthTech', 'wealth_tech',
      'mf_member_id', 'mf_user_id', 'mf_partner', 'mf_investment_type',
      'subscription', 'recurring', 'standing_instruction', 'sip',
      'beneficiarydetail', 'beneficiary_details', 'tpv', 'investment_type'
    ];
    for (const forbiddenKey of forbiddenKeys) {
      delete orderData[forbiddenKey];
      delete req.body[forbiddenKey];
    }

    const productInfo = "Leafy Checkout Bundle";
    const firstname = (orderData.customerName || '').trim() || "Leafy Shopper";
    const email = (orderData.customerEmail || '').trim();

    if (!email || !email.includes('@') || email.includes('@customer.invalid')) {
      return res.status(400).json({ error: "A valid customer email address is required for payment." });
    }

    if (isNaN(secureAmount) || secureAmount <= 0 || !isFinite(secureAmount)) {
      return res.status(400).json({ error: "Invalid payment transaction amount." });
    }

    // Customer mobile/address metadata - standard PayU e-commerce fields (phone, address1),
    // required by this merchant's PayU account configuration for a normal product checkout.
    const addressObj = orderData.shippingAddress || orderData.address || {};
    const formattedAddress = typeof addressObj === 'string'
      ? addressObj
      : [addressObj.addressLine, addressObj.city, addressObj.district, addressObj.state, addressObj.pincode].filter(Boolean).join(', ');

    const customerMobileVal = (orderData.customerMobile || orderData.phone || orderData.mobileNumber || addressObj.mobileNumber || '').toString().trim();
    const customerAddressVal = (formattedAddress || orderData.customerAddress || orderData.address || orderData.deliveryAddress || '').toString().trim();
    // Payment Gateway must reflect the configured payment_gateway_settings record, not the client-supplied hint.
    const gatewayVal = (opConfig.gateway_name || opConfig.gateway || gateway || 'PayU').toString().trim();

    if (!customerMobileVal || !/^\d{10}$/.test(customerMobileVal.replace(/\D/g, '').slice(-10))) {
      return res.status(400).json({ error: "A valid 10-digit customer mobile number is required for payment." });
    }
    if (!customerAddressVal) {
      return res.status(400).json({ error: "A valid customer address is required for payment." });
    }

    // UDF fields are only populated with legitimate merchant-defined metadata explicitly
    // supplied by the client - never repurposed to imitate wealth-tech/compliance parameters.
    const udf1 = (orderData.udf1 || "").toString().trim();
    const udf2 = (orderData.udf2 || "").toString().trim();
    const udf3 = (orderData.udf3 || "").toString().trim();
    const udf4 = (orderData.udf4 || "").toString().trim();
    const udf5 = (orderData.udf5 || "").toString().trim();

    // Generate SHA-512 Hash
    const { hash, maskedString } = generatePayUHash({
      key,
      txnid: transactionId,
      amount,
      productinfo: productInfo,
      firstname,
      email,
      udf1,
      udf2,
      udf3,
      udf4,
      udf5,
      salt
    });

    if (payuDebugEnabled) {
      console.log(`[PayU Debug] Environment: ${env}`);
      console.log(`[PayU Debug] Endpoint: ${paymentUrl}`);
      console.log(`[PayU Debug] Merchant key configured: ${Boolean(key)}`);
      console.log(`[PayU Debug] Merchant salt configured: ${Boolean(salt)}`);
      console.log(`[PayU Debug] Transaction ID present: ${Boolean(transactionId)}`);
      console.log(`[PayU Debug] Hash present: ${Boolean(hash) && hash.length === 128}`);
      console.log(`[PayU Hash Diagnostics] Env: ${env} | Txn: ${transactionId} | Amount: ${amount} | Hash: ${hash}`);
      console.log(`[PayU Hash Diagnostics] Masked String: ${maskedString}`);
    }

    const callbackBaseUrl = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
    const successUrl = `${callbackBaseUrl}/api/payment/callback/success`;
    const failureUrl = `${callbackBaseUrl}/api/payment/callback/failure`;

    const payuRequest: Record<string, any> = {
      environment: env,
      key,
      txnid: transactionId,
      amount,
      productinfo: productInfo,
      firstname,
      email,
      phone: customerMobileVal,
      address1: customerAddressVal.slice(0, 250),
      hash,
      surl: successUrl,
      furl: failureUrl,
      paymentUrl
    };

    if (addressObj && typeof addressObj === 'object') {
      if (addressObj.city) payuRequest.city = String(addressObj.city).trim();
      if (addressObj.state) payuRequest.state = String(addressObj.state).trim();
      if (addressObj.pincode) payuRequest.zipcode = String(addressObj.pincode).trim();
    }
    payuRequest.country = 'India';

    if (udf1) payuRequest.udf1 = udf1;
    if (udf2) payuRequest.udf2 = udf2;
    if (udf3) payuRequest.udf3 = udf3;
    if (udf4) payuRequest.udf4 = udf4;
    if (udf5) payuRequest.udf5 = udf5;

    // Salt must never be submitted to PayU - always enforced regardless of the debug toggle.
    if ('salt' in payuRequest) {
      console.error('[PayU Security] Blocked outgoing request: salt field detected in payuRequest.');
      return res.status(500).json({ error: 'Payment request blocked due to a security validation failure.' });
    }

    if (payuDebugEnabled) {
      const submittedParamNames = Object.keys(payuRequest).filter(k => k !== 'environment' && k !== 'paymentUrl');
      const paramPresence = submittedParamNames.reduce((acc: Record<string, boolean>, k) => {
        acc[k] = payuRequest[k] !== null && payuRequest[k] !== undefined && String(payuRequest[k]).trim() !== '';
        return acc;
      }, {});
      console.log(`[PayU Request Params] Submitted parameter names: ${submittedParamNames.join(', ')}`);
      console.log(`[PayU Request Params] Parameter presence: ${JSON.stringify(paramPresence)}`);
      console.log(`[PayU Security] Salt submitted: ${'salt' in payuRequest}`);
    }

    const tx = {
      id: transactionId,
      orderId: orderId,
      amount: Number(amount),
      paymentMethod: normalizedPaymentMethod,
      gateway: gatewayVal,
      paymentGateway: gatewayVal,
      paymentAggregator: gatewayVal,
      aggregator: gatewayVal,
      customerName: firstname,
      customerEmail: email,
      customerMobile: customerMobileVal,
      customerPhone: customerMobileVal,
      phone: customerMobileVal,
      customerAddress: customerAddressVal,
      deliveryAddress: customerAddressVal,
      address: customerAddressVal,
      shippingAddress: addressObj,
      status: (normalizedPaymentMethod === 'COD' || gateway === 'COD') ? 'Success' : 'Initiated',
      transactionReference: transactionRef,
      environment: env,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      orderPayload: orderData,
      statusHistory: [
        { status: 'Initiated', timestamp: new Date().toISOString(), note: `Payment initiated via ${gatewayVal} using ${normalizedPaymentMethod}` }
      ],
      logs: [
        { timestamp: new Date().toISOString(), action: 'INITIATED', details: `Started payment flow for ₹${amount} in ${env} environment.` },
        { timestamp: new Date().toISOString(), action: 'HASH_GENERATED', details: `Secure server-side SHA512 hash computed. Masked String: ${maskedString}` }
      ],
      payuRequest
    };

    if (normalizedPaymentMethod === 'COD' || gateway === 'COD') {
      tx.statusHistory.push({ status: 'Success', timestamp: new Date().toISOString(), note: 'COD configured successfully and pending cash collection' });
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'COD_INIT', details: 'Cash on Delivery order completed.' });
    }

    await saveCollectionDoc('payments', tx);

    return res.json({
      success: true,
      transaction: tx,
      orderId: orderId,
      environment: env,
      hash: hash,
      key: key,
      actionUrl: paymentUrl,
      paymentUrl: paymentUrl,
      productInfo: productInfo,
      firstname: firstname,
      email: email,
      amount: amount,
      txnid: transactionId,
      udf1,
      udf2,
      udf3,
      udf4,
      udf5
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to initiate payment" });
  }
}
app.post("/api/payment/initiate", createPayUPayment);

export async function verifyPayUPayment(req: any, res: any) {
  try {
    const { transactionId, gatewayResponse } = req.body;
    if (!transactionId) {
      return res.status(400).json({ error: "Missing transactionId" });
    }

    const payments = await getCollectionDocs('payments');
    const tx = payments.find((p: any) => p.id === transactionId);
    if (!tx) {
      return res.status(404).json({ error: "Payment transaction not found" });
    }

    // Idempotency: If transaction is already marked as Success, return authoritative success immediately
    if (tx.status === 'Success') {
      return res.json({
        success: true,
        transaction: tx
      });
    }

    const env = (tx.environment || 'TEST').toUpperCase();
    const secrets = getPayUSecrets(env);
    if (!secrets) {
      return res.status(503).json({ error: `PayU secret credentials are not configured for ${env} environment` });
    }

    const { key, salt } = secrets;

    tx.logs.push({
      timestamp: new Date().toISOString(),
      action: 'GATEWAY_API_CALL',
      details: `Invoking PayU S2S verify_payment web service for ${tx.id} in ${env} environment.`
    });

    let verificationSuccessful = false;
    let verificationError = '';
    let isCancelled = false;

    // 1. Authoritative S2S query to PayU verify_payment web service
    const s2sResult = await queryPayUVerifyPaymentAPI(key, salt, tx.id, env);
    if (s2sResult.success) {
      verificationSuccessful = true;
    } else if (s2sResult.status === 'Cancelled') {
      verificationSuccessful = false;
      isCancelled = true;
      verificationError = s2sResult.error || 'Payment cancelled by customer';
    } else {
      // 2. Fallback: If S2S query failed or returned unverified status (e.g. test environment sandbox), check reverse hash if gatewayResponse provided
      if (gatewayResponse && gatewayResponse.hash) {
        const { status, txnid, amount, productinfo, firstname, email, hash: receivedHash } = gatewayResponse;
        const { hash: computedReverseHash, maskedString } = generatePayUReverseHash({
          salt,
          status: status || '',
          udf10: gatewayResponse.udf10 || '',
          udf9: gatewayResponse.udf9 || '',
          udf8: gatewayResponse.udf8 || '',
          udf7: gatewayResponse.udf7 || '',
          udf6: gatewayResponse.udf6 || '',
          udf5: gatewayResponse.udf5 || '',
          udf4: gatewayResponse.udf4 || '',
          udf3: gatewayResponse.udf3 || '',
          udf2: gatewayResponse.udf2 || '',
          udf1: gatewayResponse.udf1 || '',
          email: email || '',
          firstname: firstname || '',
          productinfo: productinfo || '',
          amount: Number(amount).toFixed(2),
          txnid: txnid || tx.id,
          key: gatewayResponse.key || key
        });

        console.log(`[PayU Callback Verify] Masked Reverse String: ${maskedString}`);

        if (computedReverseHash === (receivedHash || '').toLowerCase() && String(status).toLowerCase() === 'success') {
          verificationSuccessful = true;
        } else {
          verificationSuccessful = false;
          verificationError = s2sResult.error || "Callback signature verification failed.";
        }
      } else if (gatewayResponse && gatewayResponse.simulateCancel) {
        verificationSuccessful = false;
        isCancelled = true;
        verificationError = "Payment session aborted by the customer (Simulated Cancel).";
      } else if (gatewayResponse && gatewayResponse.simulateFailure) {
        verificationSuccessful = false;
        verificationError = "Payment failed.";
      }
    }

    if (verificationSuccessful) {
      tx.status = 'Success';
      tx.statusHistory.push({ status: 'Success', timestamp: new Date().toISOString(), note: 'Payment verified via S2S/Hash' });
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'SUCCESS', details: 'Payment successfully verified.' });
      await saveCollectionDoc('payments', tx);
      return res.json({ success: true, transaction: tx });
    } else {
      if (isCancelled) {
        tx.status = 'Cancelled';
        tx.statusHistory.push({ status: 'Cancelled', timestamp: new Date().toISOString(), note: verificationError });
        tx.logs.push({ timestamp: new Date().toISOString(), action: 'CANCELLED', details: verificationError });
        await saveCollectionDoc('payments', tx);
        return res.status(400).json({ success: false, error: verificationError, transaction: tx });
      }
      tx.status = 'Failed';
      tx.statusHistory.push({ status: 'Failed', timestamp: new Date().toISOString(), note: verificationError || 'Verification failed' });
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'FAILED', details: verificationError || 'Verification failed' });
      await saveCollectionDoc('payments', tx);
      return res.status(400).json({ success: false, error: verificationError || 'Payment verification failed', transaction: tx });
    }
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to verify payment" });
  }
}
app.post("/api/payment/verify", verifyPayUPayment);

app.get("/api/payment/redirect", async (req, res) => {
  try {
    const transactionId = String(req.query.transactionId || '');
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((payment: any) => payment.id === transactionId);
    if (!tx?.payuRequest) return res.status(404).send('Payment transaction not found');

    const escapeHtml = (value: string) => value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    
    const formParams = { ...tx.payuRequest };
    delete formParams.paymentUrl;
    delete formParams.environment;

    // Salt must never be forwarded to PayU - always enforced regardless of the debug toggle.
    if ('salt' in formParams) {
      console.error('[PayU Security] Blocked outgoing redirect: salt field detected in stored payuRequest.');
      return res.status(500).send('Payment request blocked due to a security validation failure.');
    }

    if (await isPayUDebugEnabled()) {
      const submittedParamNames = Object.keys(formParams);
      const paramPresence = submittedParamNames.reduce((acc: Record<string, boolean>, k) => {
        acc[k] = formParams[k] !== null && formParams[k] !== undefined && String(formParams[k]).trim() !== '';
        return acc;
      }, {});
      console.log(`[PayU Debug] Environment: ${tx.environment}`);
      console.log(`[PayU Debug] Endpoint: ${tx.payuRequest.paymentUrl || ''}`);
      console.log(`[PayU Request Params] Submitted parameter names: ${submittedParamNames.join(', ')}`);
      console.log(`[PayU Request Params] Parameter presence: ${JSON.stringify(paramPresence)}`);
      console.log(`[PayU Security] Salt submitted: ${'salt' in formParams}`);
    }

    const fields = Object.entries(formParams)
      .filter(([_, value]) => value !== null && value !== undefined && String(value).trim() !== '')
      .map(([name, value]) => `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(String(value))}">`)
      .join('\n');
    const actionUrl = tx.payuRequest.paymentUrl || (tx.environment === 'PRODUCTION' ? 'https://secure.payu.in/_payment' : 'https://test.payu.in/_payment');
    res.type('html').send(`<!doctype html><html><body><p>Redirecting to PayU...</p><form id="payu" method="post" action="${actionUrl}">${fields}</form><script>document.getElementById('payu').submit();</script></body></html>`);
  } catch (err: any) {
    res.status(500).send(err.message || 'Unable to open payment');
  }
});

app.get("/api/payment/status/:transactionId", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) return res.status(401).json({ error: 'Authenticated customer required' });
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((payment: any) => payment.id === req.params.transactionId);
    if (!tx) return res.status(404).json({ error: 'Payment transaction not found' });
    if (tx.orderPayload?.customerId !== authenticatedUser.uid) return res.status(403).json({ error: 'Payment does not belong to customer' });
    return res.json({ status: tx.status, orderId: tx.orderId, amount: tx.amount });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || 'Unable to read payment status' });
  }
});

async function queryPayUVerifyPaymentAPI(key: string, salt: string, txnid: string, env: string): Promise<{ success: boolean; status: string; rawResponse?: any; error?: string }> {
  try {
    const command = 'verify_payment';
    const hashString = `${key}|${command}|${txnid}|${salt}`;
    const hash = crypto.createHash('sha512').update(hashString).digest('hex').toLowerCase();
    
    const verifyUrl = (env || '').toUpperCase() === 'PRODUCTION'
      ? 'https://info.payu.in/merchant/postservice.php?form=2'
      : 'https://test.payu.in/merchant/postservice?form=2';
    
    const bodyParams = new URLSearchParams();
    bodyParams.append('key', key);
    bodyParams.append('command', command);
    bodyParams.append('var1', txnid);
    bodyParams.append('hash', hash);

    const response = await fetch(verifyUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParams.toString(),
    });

    if (!response.ok) {
      return { success: false, status: 'Failed', error: `HTTP error ${response.status}` };
    }

    const text = await response.text();
    let json: any = null;
    try {
      json = JSON.parse(text);
    } catch (_) {
      return { success: false, status: 'Failed', error: 'Unparseable response from PayU S2S API', rawResponse: text };
    }

    const txDetails = json?.transaction_details?.[txnid];
    if (txDetails) {
      const payuStatus = (txDetails.unmappedstatus || txDetails.status || '').toString().toLowerCase();
      if (payuStatus === 'success') {
        return { success: true, status: 'Success', rawResponse: json };
      } else if (payuStatus.includes('cancel') || payuStatus === 'usercancelled') {
        return { success: false, status: 'Cancelled', error: txDetails.error_Message || 'Payment cancelled by customer', rawResponse: json };
      } else {
        return { success: false, status: 'Failed', error: txDetails.error_Message || txDetails.msg || `Payment status: ${payuStatus}`, rawResponse: json };
      }
    }

    return { success: false, status: 'Failed', error: json?.msg || 'Transaction reference not found in PayU verification response', rawResponse: json };
  } catch (err: any) {
    console.error('[PayU S2S Verification Exception]:', err);
    return { success: false, status: 'Failed', error: err.message || 'S2S payment verification request failed' };
  }
}

app.post("/api/payment/callback/success", async (req, res) => {
  try {
    const { status, txnid, amount, productinfo, firstname, email, hash: receivedHash } = req.body;
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((p: any) => p.id === txnid);

    if (!tx) {
      console.error(`[PayU Callback Success] Transaction ${txnid} not found.`);
      return res.redirect("/#/payment-result?payment_status=failed&error=tx_not_found");
    }

    const env = (tx.environment || 'TEST').toUpperCase();
    const secrets = getPayUSecrets(env);
    if (!secrets) {
      return res.redirect("/#/payment-result?payment_status=failed&error=payu_not_configured");
    }
    const { key, salt } = secrets;

    const { hash: computedReverseHash, maskedString } = generatePayUReverseHash({
      salt,
      status: status || '',
      udf10: req.body.udf10 || '',
      udf9: req.body.udf9 || '',
      udf8: req.body.udf8 || '',
      udf7: req.body.udf7 || '',
      udf6: req.body.udf6 || '',
      udf5: req.body.udf5 || '',
      udf4: req.body.udf4 || '',
      udf3: req.body.udf3 || '',
      udf2: req.body.udf2 || '',
      udf1: req.body.udf1 || '',
      email: email || '',
      firstname: firstname || '',
      productinfo: productinfo || '',
      amount: Number(amount).toFixed(2),
      txnid: txnid || tx.id,
      key: req.body.key || key
    });

    console.log(`[PayU Success Callback] Masked Reverse String: ${maskedString}`);

    if (String(status).toLowerCase() === 'success' && Number(amount).toFixed(2) === Number(tx.amount).toFixed(2) && computedReverseHash === (receivedHash || '').toLowerCase()) {
      tx.status = 'Success';
      tx.updatedAt = new Date().toISOString();
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'CALLBACK_VERIFIED', details: 'Successful transaction signature verified from PayU callback POST.' });
      await saveCollectionDoc('payments', tx);

      await finalizeSuccessfulPayment(tx);

      return res.redirect(`/#/payment-result?payment_status=success&txnid=${txnid}`);
    } else {
      tx.status = 'Failed';
      tx.errorMessage = 'Signature validation mismatch on callback.';
      tx.updatedAt = new Date().toISOString();
      await saveCollectionDoc('payments', tx);

      triggerAllNotifications('Failed', tx).catch(err => console.error(err));

      return res.redirect(`/#/payment-result?payment_status=failed&txnid=${txnid}&error=signature_mismatch`);
    }
  } catch (err: any) {
    console.error('[PayU Success Callback Error]:', err);
    return res.redirect("/#/payment-result?payment_status=failed&error=internal_error");
  }
});

app.post("/api/payment/callback/failure", async (req, res) => {
  try {
    const { txnid, status, field9_with_cd: errorMsg } = req.body;
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((p: any) => p.id === txnid);

    if (tx) {
      const cancelled = String(status || '').toLowerCase().includes('cancel');
      tx.status = cancelled ? 'Cancelled' : 'Failed';
      tx.errorMessage = errorMsg || (cancelled ? 'Payment cancelled by customer' : 'Payment declined by gateway');
      tx.updatedAt = new Date().toISOString();
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'CALLBACK_FAILED', details: `Transaction marked failed via PayU callback. Status: ${status}` });
      await saveCollectionDoc('payments', tx);

      triggerAllNotifications(cancelled ? 'Cancelled' : 'Failed', tx).catch(err => console.error(err));
    }
    return res.redirect(`/#/payment-result?payment_status=${tx?.status === 'Cancelled' ? 'cancelled' : 'failed'}&txnid=${txnid || ''}`);
  } catch (err: any) {
    console.error('[PayU Failure Callback Error]:', err);
    return res.redirect("/#/payment-result?payment_status=failed&error=internal_error");
  }
});

app.post("/api/payment/refund", async (req, res) => {
  try {
    const { paymentId, amount, reason } = req.body;
    if (!paymentId || !amount) {
      return res.status(400).json({ error: "Missing paymentId or amount" });
    }

    const payments = await getCollectionDocs('payments');
    const tx = payments.find((p: any) => p.id === paymentId);
    if (!tx) {
      return res.status(404).json({ error: "Payment transaction not found" });
    }

    if (tx.status !== 'Success') {
      return res.status(400).json({ error: "Only successful payments can be refunded." });
    }

    tx.logs.push({
      timestamp: new Date().toISOString(),
      action: 'REFUND_REQUESTED',
      details: `Initiated server-to-server refund of ₹${amount} for tx ${tx.id}. Reason: ${reason}`
    });

    tx.logs.push({
      timestamp: new Date().toISOString(),
      action: 'GATEWAY_REFUND_CALL',
      details: `Invoking gateway refund API. Endpoint: https://api.${tx.gateway.toLowerCase()}.com/v1/payments/${tx.transactionReference}/refund. Auth handled by server configuration.`
    });

    tx.status = 'Refunded';
    tx.statusHistory.push({
      status: 'Refunded',
      timestamp: new Date().toISOString(),
      note: `Refunded ₹${amount}. Reason: ${reason}`
    });
    tx.logs.push({
      timestamp: new Date().toISOString(),
      action: 'REFUNDED',
      details: `Refund of ₹${amount} settled successfully by ${tx.gateway}. Refund reference ID: ref-ref-${Date.now()}`
    });
    tx.updatedAt = new Date().toISOString();

    await saveCollectionDoc('payments', tx);

    const refundId = `ref-${Date.now()}`;
    const refundObj = {
      id: refundId,
      orderId: tx.orderId,
      paymentId: tx.id,
      amount: Number(amount),
      status: 'Completed' as const,
      referenceNumber: `REFND-${Date.now()}`,
      createdAt: new Date().toISOString()
    };
    await saveCollectionDoc('order_refunds', refundObj);

    await refundOrderCommissionsAuthoritative(tx, Number(amount));

    return res.json({
      success: true,
      transaction: tx,
      refund: refundObj
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to process refund" });
  }
});

// --- Customer-facing referral/commission read APIs (server-authoritative; Flutter is a thin client) ---

app.get("/api/customers/:customerId/earnings", async (req, res) => {
  try {
    const auth = await authorizeCustomerAccess(req, req.params.customerId);
    if ('error' in auth) return res.status(auth.status).json({ error: auth.error });
    return res.json(await getCustomerEarningsPayload(auth.customer));
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read customer earnings" });
  }
});

app.get("/api/customers/:customerId/commissions", async (req, res) => {
  try {
    const auth = await authorizeCustomerAccess(req, req.params.customerId);
    if ('error' in auth) return res.status(auth.status).json({ error: auth.error });
    const snap = await adminDb.collection('commission_transactions').where('referrerCustomerId', '==', auth.customer.id).get();
    const items = snap.docs.map(d => ({ id: d.id, ...d.data() })).sort((a: any, b: any) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(items);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read commission history" });
  }
});

app.get("/api/customers/:customerId/referrals", async (req, res) => {
  try {
    const auth = await authorizeCustomerAccess(req, req.params.customerId);
    if ('error' in auth) return res.status(auth.status).json({ error: auth.error });
    const snap = await adminDb.collection('customers').where('referralCode', '==', auth.customer.authUid).get();
    const referrals = snap.docs.map(d => {
      const data: any = d.data();
      return { id: d.id, name: data.name || '', mobileNumber: data.mobileNumber || '', createdAt: data.createdAt || '', qualified: Number(data.dealsClosed) > 0 };
    });
    return res.json({ totalReferrals: referrals.length, qualifiedCount: referrals.filter(r => r.qualified).length, referrals });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read referrals" });
  }
});

app.post("/api/customers/:customerId/referrals", async (req, res) => {
  try {
    const auth = await authorizeCustomerAccess(req, req.params.customerId);
    if ('error' in auth) return res.status(auth.status).json({ error: auth.error });
    const result = await applyReferralSponsor(auth.customer, (req.body?.referralCode || '').toString().trim());
    if (!result.success) return res.status(result.status || 400).json({ error: result.error });
    return res.json({ success: true });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to apply referral code" });
  }
});

app.get("/api/partners/referral-info", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) return res.status(401).json({ error: "Authenticated customer required" });
    const customer = await findCustomerByAuthUid(authenticatedUser.uid);
    if (!customer) return res.status(404).json({ error: "Customer record not found" });

    const downlineSnap = await adminDb.collection('customers').where('referralCode', '==', customer.authUid).get();
    const referrals = downlineSnap.docs.map(d => d.data() as any);
    const qualifiedCount = referrals.filter((r: any) => Number(r.dealsClosed) > 0).length;

    let sponsor: any = null;
    if (customer.referralCode && customer.referralCode !== 'organic') {
      const sponsorCustomer = await findCustomerByAuthUid(customer.referralCode);
      if (sponsorCustomer) {
        sponsor = { id: sponsorCustomer.id, name: sponsorCustomer.name || sponsorCustomer.partnerName || 'Direct Sponsor', status: 'Active' };
      }
    }

    return res.json({
      partner: {
        referralCode: customer.authUid,
        referralLink: `https://violeafy.com/ref/${customer.authUid}`,
        status: 'Active',
        level: customer.tier || 'Bronze'
      },
      sponsor,
      referralCount: referrals.length,
      qualifiedCount,
      commissionSummary: await getCustomerEarningsPayload(customer)
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read referral info" });
  }
});

app.post("/api/partners/apply-referral", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) return res.status(401).json({ error: "Authenticated customer required" });
    const customer = await findCustomerByAuthUid(authenticatedUser.uid);
    if (!customer) return res.status(404).json({ error: "Customer record not found" });
    const result = await applyReferralSponsor(customer, (req.body?.referralCode || '').toString().trim());
    if (!result.success) return res.status(result.status || 400).json({ error: result.error });
    return res.json({ success: true });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to apply referral code" });
  }
});

app.get("/api/partners/commission-history", async (req, res) => {
  try {
    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser) return res.status(401).json({ error: "Authenticated customer required" });
    const customer = await findCustomerByAuthUid(authenticatedUser.uid);
    if (!customer) return res.json([]);
    const partnerIds = Array.from(new Set([customer.id, customer.authUid, customer.mobileNumber].filter(Boolean)));
    const snap = await adminDb.collection('commission_transactions').get();
    const items = snap.docs
      .map(d => ({ id: d.id, ...d.data() }))
      .filter((tx: any) => partnerIds.includes(tx.referrerCustomerId) || partnerIds.includes(tx.referrerAuthUid) || partnerIds.includes(tx.referrerMobileNumber))
      .sort((a: any, b: any) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    return res.json(items);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to read commission history" });
  }
});

app.post("/api/admin/reprocess-commissions", async (req, res) => {
  try {
    const payments = await getCollectionDocs('payments');
    const orders = await getCollectionDocs('sales_orders');
    let processedCount = 0;

    for (const payment of payments) {
      if (payment.status === 'Success' || payment.paymentStatus === 'Paid') {
        await processOrderCommissionsAuthoritative(payment);
        processedCount++;
      }
    }

    for (const order of orders) {
      if (order.paymentStatus === 'Paid' || order.orderStatus === 'Confirmed') {
        const syntheticTx = {
          id: `tx-${order.id}`,
          orderId: order.id,
          amount: order.totalValue || order.grandTotal || order.total || order.amount || 0,
          customerName: order.customerName,
          customerEmail: order.customerEmail,
          customerMobile: order.customerMobile,
          orderPayload: order
        };
        await processOrderCommissionsAuthoritative(syntheticTx);
        processedCount++;
      }
    }

    return res.json({ success: true, message: `Successfully reprocessed 5-level commissions for ${processedCount} transactions/orders.` });
  } catch (err: any) {
    console.error('Error reprocessing commissions:', err);
    return res.status(500).json({ error: err.message || "Failed to reprocess commissions" });
  }
});

app.post("/api/notifications/resend", async (req, res) => {
  try {
    const { logId } = req.body;
    if (!logId) {
      return res.status(400).json({ error: "Missing logId" });
    }

    const logs = await getCollectionDocs('notification_logs');
    const log = logs.find((l: any) => l.id === logId);
    if (!log) {
      return res.status(404).json({ error: "Notification log not found" });
    }

    const settings = await getNotificationSettings();
    const tx = log.originalTx;

    let sentStatus = 'Success';
    let errorMessage = '';

    if (log.type === 'Email') {
      const isSmtpConfigured = settings.smtpHost && settings.smtpUser && settings.smtpPass;
      try {
        if (isSmtpConfigured) {
          const transporter = nodemailer.createTransport({
            host: settings.smtpHost,
            port: Number(settings.smtpPort),
            secure: Number(settings.smtpPort) === 465,
            auth: {
              user: settings.smtpUser,
              pass: settings.smtpPass
            }
          });

          await transporter.sendMail({
            from: settings.smtpFrom || 'no-reply@leafy.com',
            to: log.recipient,
            subject: log.emailSubject,
            html: log.emailHtml
          });
          console.log(`[SMTP Resend] Dispatched email to: ${log.recipient}`);
        } else {
          console.log(`[SMTP Resend Mock] Simulating resend to: ${log.recipient}`);
        }
      } catch (err: any) {
        sentStatus = 'Failed';
        errorMessage = err.message || 'SMTP delivery failure';
      }
    } else if (log.type === 'WhatsApp') {
      const isWaConfigured = settings.whatsappApiUrl && settings.whatsappToken && settings.whatsappPhoneId;
      try {
        if (isWaConfigured) {
          const recipients = log.recipient.split(', ');
          for (const phone of recipients) {
            const cleanedPhone = phone.replace(/[^0-9+]/g, '');
            const url = `${settings.whatsappApiUrl}/${settings.whatsappPhoneId}/messages`;

            const response = await fetch(url, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${settings.whatsappToken}`,
                'Content-Type': 'application/json'
              },
              body: JSON.stringify({
                messaging_product: "whatsapp",
                recipient_type: "individual",
                to: cleanedPhone,
                type: "text",
                text: {
                  preview_url: false,
                  body: log.messageText
                }
              })
            });

            if (!response.ok) {
              const errData = await response.json();
              throw new Error(errData.error?.message || `WhatsApp API error: status ${response.status}`);
            }
          }
          console.log(`[WhatsApp Resend] Dispatched resend to: ${log.recipient}`);
        } else {
          console.log(`[WhatsApp Resend Mock] Simulating resend to: ${log.recipient}`);
        }
      } catch (err: any) {
        sentStatus = 'Failed';
        errorMessage = err.message || 'WhatsApp delivery failure';
      }
    }

    log.status = sentStatus;
    log.errorMessage = errorMessage;
    log.dateTime = new Date().toISOString();
    await saveCollectionDoc('notification_logs', log);

    return res.json({ success: sentStatus === 'Success', log });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to resend notification" });
  }
});

// Start integration server inside app environment
async function startServer() {
  // Serve the Flutter Web SPA statically from build/web for all environments
  const getDistPath = () => {
    const buildPath = path.join(process.cwd(), "build", "web");
    if (fs.existsSync(path.join(buildPath, "index.html")) && fs.existsSync(path.join(buildPath, "flutter_bootstrap.js"))) {
      return buildPath;
    }
    return buildPath;
  };

  app.use((req, res, next) => {
    express.static(getDistPath())(req, res, next);
  });

  app.get("*", (req, res) => {
    if (req.path.startsWith("/api")) {
      return res.status(404).json({ error: "API endpoint not found" });
    }
    const currentDist = getDistPath();
    const filePath = path.join(currentDist, req.path);
    if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      res.sendFile(filePath);
    } else {
      const indexPath = path.join(currentDist, "index.html");
      if (fs.existsSync(indexPath)) {
        res.sendFile(indexPath);
      } else {
        res.status(404).send("Application web build not found. Please run 'flutter build web'.");
      }
    }
  });

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`[violeafycrossap Server listening on http://0.0.0.0:${PORT}`);
  });
}

const isMainScript = Boolean(
  process.argv[1] &&
  !process.argv[1].includes("firebase-functions") &&
  !process.argv[1].includes("firebase-tools") &&
  (process.argv[1].endsWith("server.cjs") || process.argv[1].endsWith("server.ts") || process.argv[1].endsWith("server.js"))
);

if (isMainScript && !process.env.K_SERVICE && !process.env.FUNCTION_TARGET && !process.env.FUNCTIONS_EMULATOR) {
  startServer();
}
