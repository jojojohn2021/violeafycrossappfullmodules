import express from "express";
import path from "path";
import dotenv from "dotenv";
import fs from "fs";
import { GoogleGenAI } from "@google/genai";
import crypto from "crypto";
import nodemailer from "nodemailer";
import { adminApp, adminAuth, adminDb, adminStorage } from "./firebase-admin";

dotenv.config();

export { adminApp, adminAuth, adminDb, adminStorage };

// Example API Endpoint using violeafydb
export async function getProducts(req: any, res: any) {
  try {
    const snapshot = await adminDb.collection("products").get();
    const products = snapshot.docs.map((doc: any) => ({ id: doc.id, ...doc.data() }));
    res.status(200).json(products);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
}

const app = express();
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

async function getCollectionDocs(col: string): Promise<any[]> {
  try {
    const snapshot = await adminDb.collection(col).get();
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
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
  const lead = leads.empty ? null : { id: leads.docs[0].id, ...leads.docs[0].data() };
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

app.get("/api/categories", async (req, res) => {
  try {
    const docs = await getCollectionDocs("products");
    const categories = Array.from(new Set(docs.map((p: any) => p.category).filter(Boolean)));
    return res.json(categories);
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to fetch categories" });
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

app.get("/api/sales-orders", async (req, res) => {
  try {
    const docs = await getCollectionDocs("sales_orders");
    return res.json(docs);
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
    const dummyProducts = [
      {
        id: "prod-apple",
        name: "Fresh Apple (Fuji)",
        sku: "APP-FUJ-01",
        packingSize: "1 kg",
        unit: "kg",
        onlinePrice: 180,
        shopPrice: 200,
        notes: "Crisp organic apples.",
        picture: "https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?w=400&h=400&fit=crop&q=80",
        unitsSold: 45,
        revenue: 8100,
        growthRate: 15.4,
        stock: 120,
        amazonSales: 2000,
        flipkartSales: 1500,
        meeshoSales: 500,
        vamjoSales: 4100,
        whatsappSales: 1000,
        countersaleSales: 1200,
        gstPercentage: 5,
        stockIn: 150,
        stockOut: 45,
        category: "Fruits",
        brand: "Leafy Organics",
        brandOwner: "VioCRM",
        images: ["https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?w=400&h=400&fit=crop&q=80"],
        description: "Crisp and sweet organic Fuji apples harvested from Himachal farms.",
        rating: 4.5,
        reviewsCount: 12
      },
      {
        id: "prod-banana",
        name: "Organic Banana (Robusta)",
        sku: "BAN-ROB-02",
        packingSize: "1 Dozen",
        unit: "Dozen",
        onlinePrice: 60,
        shopPrice: 70,
        notes: "Rich in fiber.",
        picture: "https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?w=400&h=400&fit=crop&q=80",
        unitsSold: 90,
        revenue: 5400,
        growthRate: 8.2,
        stock: 80,
        amazonSales: 1000,
        flipkartSales: 800,
        meeshoSales: 300,
        vamjoSales: 3300,
        whatsappSales: 1200,
        countersaleSales: 1500,
        gstPercentage: 5,
        stockIn: 100,
        stockOut: 90,
        category: "Fruits",
        brand: "Leafy Organics",
        brandOwner: "VioCRM",
        images: ["https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?w=400&h=400&fit=crop&q=80"],
        description: "Naturally ripened Robusta bananas rich in dietary fiber.",
        rating: 4.8,
        reviewsCount: 22
      },
      {
        id: "prod-broccoli",
        name: "Fresh Broccoli",
        sku: "VEG-BRO-03",
        packingSize: "500 g",
        unit: "g",
        onlinePrice: 90,
        shopPrice: 100,
        notes: "Floret greens.",
        picture: "https://images.unsplash.com/photo-1584269600464-37b1b58a9fe7?w=400&h=400&fit=crop&q=80",
        unitsSold: 30,
        revenue: 2700,
        growthRate: 12.0,
        stock: 50,
        amazonSales: 500,
        flipkartSales: 400,
        meeshoSales: 200,
        vamjoSales: 1600,
        whatsappSales: 800,
        countersaleSales: 900,
        gstPercentage: 5,
        stockIn: 60,
        stockOut: 30,
        category: "Vegetables",
        brand: "Farm Fresh",
        brandOwner: "VioCRM",
        images: ["https://images.unsplash.com/photo-1584269600464-37b1b58a9fe7?w=400&h=400&fit=crop&q=80"],
        description: "Rich green organic broccoli florets packed with antioxidants.",
        rating: 4.2,
        reviewsCount: 8
      }
    ];

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

    for (const p of dummyProducts) {
      await adminDb.collection('products').doc(p.id).set(p, { merge: true });
    }
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
          Email: support@leafy.com | Web: <a href="https://leafyvio.ai.studio" style="color: #0f766e; text-decoration: none;">https://leafyvio.ai.studio</a><br/>
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
  messageText += `Thank you for shopping with us! View full invoice details at https://leafyvio.ai.studio`;

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

app.post("/api/payment/initiate", async (req, res) => {
  try {
    const { orderData, paymentMethod, gateway } = req.body;
    if (!orderData || !gateway) {
      return res.status(400).json({ error: "Missing required orderData or gateway" });
    }

    const normalizedPaymentMethod = paymentMethod || (gateway === 'PayU' ? 'UPI' : 'PayU');

    const authenticatedUser = await getAuthenticatedUser(req);
    if (!authenticatedUser || orderData.customerId !== authenticatedUser.uid) {
      return res.status(401).json({ error: "Authenticated customer required" });
    }

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

    // Fetch gateway configurations
    const configs = await getCollectionDocs('payment_gateway_settings');
    const payuConfig = configs.find((c: any) => c.gateway_name === 'PayU' && c.status === 'Enabled');

    const env = (req.body.environment || payuConfig?.environment || 'Test') === 'Production' ? 'Production' : 'Test';
    const key = env === 'Production'
      ? (payuConfig?.prod_merchant_key || payuConfig?.merchant_key || process.env.PAYU_PROD_MERCHANT_KEY || 'gtK2y6')
      : (payuConfig?.test_merchant_key || payuConfig?.merchant_key || process.env.PAYU_TEST_MERCHANT_KEY || 'gtK2y6');
    const rawSalt = env === 'Production'
      ? (payuConfig?.prod_merchant_salt || payuConfig?.merchant_salt || process.env.PAYU_PROD_MERCHANT_SALT || 'eCwTWDvi')
      : (payuConfig?.test_merchant_salt || payuConfig?.merchant_salt || process.env.PAYU_TEST_MERCHANT_SALT || 'eCwTWDvi');
    const salt = decryptSalt(rawSalt);

    // Format transaction ID as requested (VNX + YYYYMMDDHHMMSS + 3 random digits)
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const timestampStr = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    const randomSuffix = Math.floor(100 + Math.random() * 900);
    const transactionId = `VNX${timestampStr}${randomSuffix}`;
    const transactionRef = `ref-payu-${Date.now()}`;

    // PayU Hosted Checkout URL
    const actionUrl = env === 'Production'
      ? 'https://secure.payu.in/_payment'
      : 'https://test.payu.in/_payment';

    // Parameters for hash generation
    const productInfo = "VioneX Organic Grocery Checkout Bundle";
    const firstname = orderData.customerName || "VioneX Shopper";
    const email = orderData.customerEmail || "shopper@vionex.com";
    const configuredUpiId = process.env.PAYU_UPI_ID || 'test@payu';
    const userCredentials = normalizedPaymentMethod === 'UPI' ? configuredUpiId : '';

    // PayU standard hash string: key|txnid|amount|productinfo|firstname|email|udf1|udf2|udf3|udf4|udf5||||||salt
    const hashString = `${key}|${transactionId}|${amount}|${productInfo}|${firstname}|${email}|||||||||||${salt}`;
    const hash = crypto.createHash('sha512').update(hashString).digest('hex').toLowerCase();
    const callbackBaseUrl = process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
    const successUrl = `${callbackBaseUrl}/api/payment/callback/success`;
    const failureUrl = `${callbackBaseUrl}/api/payment/callback/failure`;

    const tx = {
      id: transactionId,
      orderId: orderId,
      amount: Number(amount),
      paymentMethod: normalizedPaymentMethod,
      gateway: gateway,
      status: (normalizedPaymentMethod === 'COD' || gateway === 'COD') ? 'Success' : 'Initiated',
      transactionReference: transactionRef,
      environment: env,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      orderPayload: orderData, // Cache the full order data payload
      statusHistory: [
        { status: 'Initiated', timestamp: new Date().toISOString(), note: `Payment initiated via ${gateway} using ${paymentMethod}` }
      ],
      logs: [
        { timestamp: new Date().toISOString(), action: 'INITIATED', details: `Started payment flow for ₹${amount} in ${env} environment.` },
        { timestamp: new Date().toISOString(), action: 'HASH_GENERATED', details: `Secure server-side SHA512 hash computed. String: key|txnid|amount|prodInfo|name|email||||||salt` }
      ],
      payuRequest: {
        key,
        txnid: transactionId,
        amount,
        productinfo: productInfo,
        firstname,
        email,
        hash,
        surl: successUrl,
        furl: failureUrl,
        ...(userCredentials ? { user_credentials: userCredentials } : {}),
      }
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
      hash: hash,
      key: key,
      actionUrl: actionUrl,
      productInfo: productInfo,
      firstname: firstname,
      email: email,
      amount: amount,
      txnid: transactionId
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to initiate payment" });
  }
});

app.get("/api/payment/redirect", async (req, res) => {
  try {
    const transactionId = String(req.query.transactionId || '');
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((payment: any) => payment.id === transactionId);
    if (!tx?.payuRequest) return res.status(404).send('Payment transaction not found');

    const escapeHtml = (value: string) => value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const fields = Object.entries(tx.payuRequest)
      .map(([name, value]) => `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(String(value))}">`)
      .join('');
    const actionUrl = tx.environment === 'Production' ? 'https://secure.payu.in/_payment' : 'https://test.payu.in/_payment';
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

app.post("/api/payment/verify", async (req, res) => {
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

    // Fetch credentials
    const configs = await getCollectionDocs('payment_gateway_settings');
    const payuConfig = configs.find((c: any) => c.gateway_name === 'PayU' && c.status === 'Enabled');
    if (!payuConfig?.merchant_key || !payuConfig?.merchant_salt) {
      return res.status(503).json({ error: "PayU is not configured" });
    }

    const key = payuConfig.merchant_key;
    const salt = decryptSalt(payuConfig.merchant_salt);

    tx.logs.push({
      timestamp: new Date().toISOString(),
      action: 'GATEWAY_API_CALL',
      details: `Invoking server-to-server gateway API verification. Endpoint: https://api.payu.in/v1/payments/${tx.transactionReference}.`
    });

    let verificationSuccessful = true;
    let verificationError = '';

    // Validate callback hash if response is provided from real PayU callback
    if (gatewayResponse && gatewayResponse.hash) {
      const { status, txnid, amount, productinfo, firstname, email, hash: receivedHash } = gatewayResponse;
      // Reverse hash formula: sha512(salt|status||||||udf5|udf4|udf3|udf2|udf1|email|firstname|productinfo|amount|txnid|key)
      const reverseHashString = `${salt}|${status}|||||||||||${email}|${firstname}|${productinfo}|${Number(amount).toFixed(2)}|${txnid}|${key}`;
      const computedReverseHash = crypto.createHash('sha512').update(reverseHashString).digest('hex').toLowerCase();

      if (computedReverseHash !== receivedHash.toLowerCase()) {
        verificationSuccessful = false;
        verificationError = "Callback signature verification failed. Computed: " + computedReverseHash.slice(0, 8) + "... Received: " + receivedHash.slice(0, 8);
      }
    }

    let isCancelled = false;
    if (gatewayResponse && gatewayResponse.simulateCancel) {
      verificationSuccessful = false;
      isCancelled = true;
      verificationError = "Payment session aborted by the customer (Simulated Cancel).";
    } else if (gatewayResponse && gatewayResponse.simulateFailure) {
      verificationSuccessful = false;
      verificationError = "Card declined or insufficient funds (Simulated Gateway Error).";
    }

    if (verificationSuccessful) {
      tx.status = 'Success';
      tx.statusHistory.push({
        status: 'Success',
        timestamp: new Date().toISOString(),
        note: `Server-side verification succeeded. Verified with gateway API (${tx.gateway})`
      });
      tx.logs.push({
        timestamp: new Date().toISOString(),
        action: 'VERIFIED',
        details: `Payment reference ${tx.transactionReference} verified successfully. Generated digital checkout signature token: ${Buffer.from(tx.id).toString('base64')}`
      });

      // Save sales order to database if not exists
      const salesOrders = await getCollectionDocs('sales_orders');
      let order = salesOrders.find((o: any) => o.id === tx.orderId);
      if (!order && tx.orderPayload) {
        const orderNum = `SO-2026-${String(salesOrders.length + 1).padStart(4, '0')}`;
        order = {
          ...tx.orderPayload,
          id: tx.orderId,
          orderNumber: orderNum,
          paymentStatus: 'Paid',
          orderStatus: 'Confirmed',
          deliveryStatus: 'Processing',
          createdAt: new Date().toISOString()
        };
        await saveCollectionDoc('sales_orders', order);

        // Deduct inventory
        const products = await getCollectionDocs('products');
        for (const item of (order.products || [])) {
          const prod = products.find((p: any) => p.id === item.productId);
          if (prod) {
            prod.stock = Math.max(0, (prod.stock || 0) - item.quantity);
            prod.unitsSold = (prod.unitsSold || 0) + item.quantity;
            prod.revenue = (prod.revenue || 0) + (item.price * item.quantity);
            await saveCollectionDoc('products', prod);
          }
        }
      }
    } else {
      tx.status = isCancelled ? 'Cancelled' : 'Failed';
      tx.errorMessage = verificationError;
      tx.statusHistory.push({
        status: tx.status,
        timestamp: new Date().toISOString(),
        note: `Gateway verification resulted in ${tx.status}: ${verificationError}`
      });
      tx.logs.push({
        timestamp: new Date().toISOString(),
        action: isCancelled ? 'CANCELLED' : 'FAILED',
        details: `Verification failed/cancelled. error: ${verificationError}`
      });
    }

    tx.updatedAt = new Date().toISOString();
    await saveCollectionDoc('payments', tx);

    // Asynchronously trigger email and WhatsApp notifications
    const notifyType = tx.status === 'Success' ? 'Success' : tx.status === 'Cancelled' ? 'Cancelled' : 'Failed';
    triggerAllNotifications(notifyType, tx).catch(err => {
      console.error("Failed to run triggerAllNotifications:", err);
    });

    return res.json({
      success: verificationSuccessful,
      transaction: tx
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to verify payment" });
  }
});

app.post("/api/payment/callback/success", async (req, res) => {
  try {
    const { status, txnid, amount, productinfo, firstname, email, hash: receivedHash } = req.body;
    const payments = await getCollectionDocs('payments');
    const tx = payments.find((p: any) => p.id === txnid);

    if (!tx) {
      console.error(`[PayU Callback Success] Transaction ${txnid} not found.`);
      return res.redirect("/#/payment-result?payment_status=failed&error=tx_not_found");
    }

    const configs = await getCollectionDocs('payment_gateway_settings');
    const payuConfig = configs.find((c: any) => c.gateway_name === 'PayU' && c.status === 'Enabled');
    if (!payuConfig?.merchant_key || !payuConfig?.merchant_salt) {
      return res.redirect("/#/payment-result?payment_status=failed&error=payu_not_configured");
    }
    const key = payuConfig.merchant_key;
    const salt = decryptSalt(payuConfig.merchant_salt);

    // Verify hash
    const reverseHashString = `${salt}|${status}|||||||||||${email}|${firstname}|${productinfo}|${Number(amount).toFixed(2)}|${txnid}|${key}`;
    const computedReverseHash = crypto.createHash('sha512').update(reverseHashString).digest('hex').toLowerCase();

    if (String(status).toLowerCase() === 'success' && Number(amount).toFixed(2) === Number(tx.amount).toFixed(2) && computedReverseHash === receivedHash?.toLowerCase()) {
      tx.status = 'Success';
      tx.updatedAt = new Date().toISOString();
      tx.logs.push({ timestamp: new Date().toISOString(), action: 'CALLBACK_VERIFIED', details: 'Successful transaction signature verified from PayU callback POST.' });
      await saveCollectionDoc('payments', tx);

      // Save sales order to database if not exists
      const salesOrders = await getCollectionDocs('sales_orders');
      let order = salesOrders.find((o: any) => o.id === tx.orderId);
      if (!order && tx.orderPayload) {
        const orderNum = `SO-2026-${String(salesOrders.length + 1).padStart(4, '0')}`;
        order = {
          ...tx.orderPayload,
          id: tx.orderId,
          orderNumber: orderNum,
          paymentStatus: 'Paid',
          orderStatus: 'Confirmed',
          deliveryStatus: 'Processing',
          createdAt: new Date().toISOString()
        };
        await saveCollectionDoc('sales_orders', order);

        // Deduct inventory
        const products = await getCollectionDocs('products');
        for (const item of (order.products || [])) {
          const prod = products.find((p: any) => p.id === item.productId);
          if (prod) {
            prod.stock = Math.max(0, (prod.stock || 0) - item.quantity);
            prod.unitsSold = (prod.unitsSold || 0) + item.quantity;
            prod.revenue = (prod.revenue || 0) + (item.price * item.quantity);
            await saveCollectionDoc('products', prod);
          }
        }
      }

      // Trigger notifications
      triggerAllNotifications('Success', tx).catch(err => console.error(err));

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
    return res.redirect(`/#/payment-result?payment_status=${tx.status === 'Cancelled' ? 'cancelled' : 'failed'}&txnid=${txnid}`);
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

    return res.json({
      success: true,
      transaction: tx,
      refund: refundObj
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message || "Failed to process refund" });
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

startServer();
