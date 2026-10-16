// Run: npx tsx --test test/whatsapp_notifier.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  validateWhatsAppConfig, validateTemplateName, normalizeInternational, extractPhoneValues,
  recipientFieldsFor, resolveRecipients, buildOrderPlacedParams, sanitizeParam,
  buildEventKey, postWithRetry, sendOrderPlacedNotification, buildTemplatePayload,
  sendPaymentOutcomeNotification, resendTemplateLog, buildPaymentOutcomeParams,
} from "../whatsapp-notifier";

// ---------- minimal in-memory Firestore fake ----------
function fakeDb(seed: Record<string, Record<string, any>>) {
  const store: Record<string, Record<string, any>> = JSON.parse(JSON.stringify(seed));
  const docRef = (col: string, id: string) => ({
    id,
    async get() { const d = store[col]?.[id]; return { id, exists: !!d, data: () => d }; },
    async set(v: any, o?: any) { store[col] ??= {}; store[col][id] = o?.merge ? { ...(store[col][id] || {}), ...v } : v; },
  });
  return {
    store,
    collection: (col: string) => ({ doc: (id: string) => ({ ...docRef(col, id), _col: col }) }),
    async runTransaction(fn: any) {
      return fn({ get: (r: any) => r.get(), set: (r: any, v: any, o: any) => r.set(v, o) });
    },
  };
}
const silent = { info() {}, warn() {}, error() {} };

const baseConfig = {
  whatsappApiUrl: "https://graph.facebook.com/v17.0",
  whatsappToken: "secret-token",
  whatsappPhoneId: "1234567890",
  whatsappTemplateOrderPlaced: "order_placed",
  successPhones1: "+918547927539",
  successPhones2: ["+91 85890 37171", "+918547927539"],
  failedPhones1: "+919999999999",
};
const order = {
  orderNumber: "SO-2026-0001",
  customerName: "Asha",
  customerMobile: "9876543210",
  createdAt: "2026-10-14T10:00:00.000Z",
  products: [{ productName: "Neem Oil", sku: "NO-1", quantity: 2 }],
  shippingAddress: { addressLine: "12 MG Road", city: "Kochi", state: "Kerala", pincode: "682001" },
};
const seed = () => ({
  global: { config: { ...baseConfig } },
  sales_orders: { "ord-1": { ...order } },
  customer_mobile_plus_code_index: { "+919876543210": { customerId: "c1", mobileNumberpluscode: "+919876543210" } },
});
function okFetch(calls: any[]) {
  return (async (url: string, init: any) => {
    calls.push({ url, body: JSON.parse(init.body), headers: init.headers });
    return { ok: true, status: 200, json: async () => ({ messages: [{ id: `wamid.${calls.length}` }] }) };
  }) as any;
}

// ---------- config validation ----------
test("config: builds endpoint from base URL", () => {
  const r = validateWhatsAppConfig(baseConfig);
  assert.ok(r.ok && r.value.endpoint === "https://graph.facebook.com/v17.0/1234567890/messages");
});
test("config: accepts full endpoint as stored", () => {
  const r = validateWhatsAppConfig({ ...baseConfig, whatsappApiUrl: "https://graph.facebook.com/v17.0/1234567890/messages" });
  assert.ok(r.ok && r.value.endpoint.endsWith("/1234567890/messages") && !r.value.endpoint.includes("messages/"));
});
test("config: rejects missing / malformed / non-https", () => {
  assert.equal(validateWhatsAppConfig(null).ok, false);
  assert.equal(validateWhatsAppConfig({ ...baseConfig, whatsappToken: " " }).ok, false);
  assert.equal(validateWhatsAppConfig({ ...baseConfig, whatsappPhoneId: "abc" }).ok, false);
  assert.equal(validateWhatsAppConfig({ ...baseConfig, whatsappApiUrl: "http://x.com" }).ok, false);
  assert.equal(validateWhatsAppConfig({ ...baseConfig, whatsappApiUrl: "not a url" }).ok, false);
});
test("template name validation", () => {
  assert.equal(validateTemplateName("order_placed").ok, true);
  assert.equal(validateTemplateName("").ok, false);
  assert.equal(validateTemplateName("Order Placed!").ok, false);
});

// ---------- stage mapping / recipients ----------
test("stage mapping: recipient fields per outcome", () => {
  assert.deepEqual(recipientFieldsFor("Success"), ["successPhones1", "successPhones2"]);
  assert.deepEqual(recipientFieldsFor("Failed"), ["failedPhones1", "failedPhones2"]);
  assert.deepEqual(recipientFieldsFor("Cancelled"), ["failedPhones1", "failedPhones2"]);
});
test("normalization: never guesses country code", () => {
  assert.deepEqual(normalizeInternational("+91 98765-43210"), { ok: true, value: "919876543210" });
  assert.deepEqual(normalizeInternational("0091 9876543210"), { ok: true, value: "919876543210" });
  assert.equal((normalizeInternational("9876543210") as any).reason, "needs_country_code");
  assert.equal(normalizeInternational("a@b.com").ok, false);
  assert.equal(normalizeInternational("+12").ok, false);
});
test("extractPhoneValues handles string, csv, array", () => {
  assert.deepEqual(extractPhoneValues("+911, +912;+913"), ["+911", "+912", "+913"]);
  assert.deepEqual(extractPhoneValues(["+911", ["+912"]]), ["+911", "+912"]);
  assert.deepEqual(extractPhoneValues(undefined), []);
});
test("resolveRecipients: index lookup + dedup + invalid skipped", async () => {
  const db = fakeDb(seed());
  const { recipients, skipped } = await resolveRecipients(db, "Success",
    order, { ...baseConfig, successPhones2: ["+918547927539", "8589037171", "ops@x.com"] });
  assert.deepEqual(recipients.map(r => r.digits), ["919876543210", "918547927539"]);
  const reasons = skipped.map(s => s.reason).sort();
  assert.deepEqual(reasons, ["duplicate_recipient", "needs_country_code", "not_a_phone_number"]);
});
test("resolveRecipients: customer not in plus-code index is skipped", async () => {
  const db = fakeDb({ ...seed(), customer_mobile_plus_code_index: {} });
  const { recipients, skipped } = await resolveRecipients(db, "Success", order, { successPhones1: "" });
  assert.equal(recipients.length, 0);
  assert.equal(skipped[0].reason, "not_found_in_customer_mobile_plus_code_index");
});

// ---------- parameters ----------
test("buildOrderPlacedParams: matches leafyearth_orderconfirm {{1}}..{{5}}", () => {
  const p = buildOrderPlacedParams({ ...order, orderNumber: "#SO-2026-0001" });
  assert.deepEqual(p, ["Asha", "purchase", "SO-2026-0001", "Neem Oil (SKU NO-1) x 2", "Will be shared on dispatch"]);
  assert.match(buildOrderPlacedParams({ ...order, estimatedDelivery: "2026-10-20" })[4], /20 Oct 2026/);
  assert.deepEqual(buildOrderPlacedParams({}), ["Customer", "purchase", "-", "-", "Will be shared on dispatch"]);
});
test("buildPaymentOutcomeParams: order and sanitization", () => {
  const p = buildPaymentOutcomeParams(order);
  assert.equal(p.length, 5);
  assert.equal(p[0], "Asha");
  assert.equal(p[1], "SO-2026-0001");
  assert.match(p[2], /14 Oct 2026/);
  assert.equal(p[3], "Neem Oil (SKU NO-1) x 2");
  assert.equal(p[4], "12 MG Road, Kochi, Kerala - 682001");
  assert.equal(sanitizeParam("a\n\tb     c"), "a b c");
  assert.equal(sanitizeParam(""), "-");
  assert.deepEqual(buildPaymentOutcomeParams({}), ["-", "-", "-", "-", "-"]);
});
test("template payload shape", () => {
  const b = buildTemplatePayload("91x", "order_placed", "en", ["a"]);
  assert.equal(b.type, "template");
  assert.equal(b.template.name, "order_placed");
  assert.deepEqual(b.template.components[0].parameters, [{ type: "text", text: "a" }]);
});

// ---------- provider failures / retries ----------
test("postWithRetry: retries transient then succeeds", async () => {
  let n = 0;
  const f: any = async () => (++n < 2
    ? { ok: false, status: 503, json: async () => ({}) }
    : { ok: true, status: 200, json: async () => ({ messages: [{ id: "wamid.X" }] }) });
  const r = await postWithRetry(f, "https://e", "t", {}, { backoffMs: 1 });
  assert.equal(r.ok, true); assert.equal(r.messageId, "wamid.X"); assert.equal(r.attempts, 2);
});
test("postWithRetry: no retry on permanent failure", async () => {
  let n = 0;
  const f: any = async () => { n++; return { ok: false, status: 400, json: async () => ({ error: { code: 132001, message: "Template does not exist" } }) }; };
  const r = await postWithRetry(f, "https://e", "t", {}, { backoffMs: 1 });
  assert.equal(n, 1); assert.equal(r.transient, false); assert.equal(r.errorCode, 132001);
});
test("postWithRetry: bounded on network errors", async () => {
  let n = 0;
  const f: any = async () => { n++; throw new Error("ECONNRESET"); };
  const r = await postWithRetry(f, "https://e", "t", {}, { backoffMs: 1, maxAttempts: 3 });
  assert.equal(n, 3); assert.equal(r.ok, false); assert.equal(r.errorMessage, "network error");
});

// ---------- orchestration ----------
test("send: accepted, logs eventKey, no token in logs", async () => {
  const db = fakeDb(seed()); const calls: any[] = [];
  const s = await sendOrderPlacedNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "ord-1");
  assert.equal(s.status, "sent"); assert.equal(s.accepted, 3);
  assert.equal(calls[0].body.template.name, "order_placed");
  const logs = Object.values(db.store.notification_logs);
  assert.equal(logs.length, 3);
  assert.ok(logs.every((l: any) => l.eventKey && l.status === "Success" && l.deliveryStatus === "Accepted"));
  assert.ok(!JSON.stringify(db.store.notification_logs).includes("secret-token"));
  assert.ok(!JSON.stringify(db.store.notification_logs).includes("9876543210"));
});
test("send: duplicate event does not resend", async () => {
  const db = fakeDb(seed()); const calls: any[] = [];
  await sendOrderPlacedNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "ord-1");
  const s2 = await sendOrderPlacedNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "ord-1");
  assert.equal(calls.length, 3); assert.equal(s2.duplicates, 3); assert.equal(s2.accepted, 0);
});
test("send: partial success when one recipient fails", async () => {
  const db = fakeDb(seed());
  const f: any = async (_u: string, init: any) => JSON.parse(init.body).to === "918547927539"
    ? { ok: false, status: 400, json: async () => ({ error: { message: "invalid recipient" } }) }
    : { ok: true, status: 200, json: async () => ({ messages: [{ id: "wamid.ok" }] }) };
  const s = await sendOrderPlacedNotification({ db, fetchImpl: f, logger: silent }, "ord-1");
  assert.equal(s.status, "partial"); assert.equal(s.accepted, 2); assert.equal(s.failed, 1);
});
test("send: missing config or template skips without calling provider", async () => {
  for (const patch of [{ whatsappToken: "" }, { whatsappTemplateOrderPlaced: "" }]) {
    const sd = seed(); Object.assign(sd.global.config, patch);
    const calls: any[] = [];
    const s = await sendOrderPlacedNotification({ db: fakeDb(sd), fetchImpl: okFetch(calls), logger: silent }, "ord-1");
    assert.equal(s.status, "skipped"); assert.equal(calls.length, 0);
  }
  const noCfg = seed() as any; delete noCfg.global;
  const s = await sendOrderPlacedNotification({ db: fakeDb(noCfg), fetchImpl: okFetch([]), logger: silent }, "ord-1");
  assert.equal(s.reason, "global/config not found");
});
test("send: missing order is skipped", async () => {
  const s = await sendOrderPlacedNotification({ db: fakeDb(seed()), fetchImpl: okFetch([]), logger: silent }, "nope");
  assert.equal(s.reason, "record not found");
});
test("eventKey is deterministic", () => {
  assert.equal(buildEventKey("o", "OrderPlaced", "91"), buildEventKey("o", "OrderPlaced", "91"));
});

// ---------- Failed / Cancelled ----------
const failedSeed = () => {
  const s: any = seed();
  s.global.config.whatsappTemplate_Failed = "payment_failed";
  s.payments = { "tx-1": { id: "tx-1", orderId: "ord-9", status: "PAYMENT_FAILED", orderPayload: { ...order, orderNumber: undefined } } };
  return s;
};
test("failed: uses whatsappTemplate_Failed + failedPhones, from payments record", async () => {
  const db = fakeDb(failedSeed()); const calls: any[] = [];
  const s = await sendPaymentOutcomeNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "Failed", "tx-1");
  assert.equal(s.accepted, 2);
  assert.ok(calls.every(c => c.body.template.name === "payment_failed"));
  assert.deepEqual(calls.map(c => c.body.to).sort(), ["919876543210", "919999999999"]);
  assert.equal(calls[0].body.template.components[0].parameters[1].text, "ord-9");
  const logs: any[] = Object.values(db.store.notification_logs);
  assert.ok(logs.every(l => l.stage === "PaymentFailed" && l.paymentId === "tx-1"));
});
test("cancelled: same template, separate stage (no cross-dedup with Failed)", async () => {
  const db = fakeDb(failedSeed()); const calls: any[] = [];
  await sendPaymentOutcomeNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "Failed", "tx-1");
  const s = await sendPaymentOutcomeNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "Cancelled", "tx-1");
  assert.equal(s.accepted, 2);
  const again = await sendPaymentOutcomeNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "Cancelled", "tx-1");
  assert.equal(again.duplicates, 2);
});
test("failed: missing whatsappTemplate_Failed skips", async () => {
  const sd = failedSeed(); delete sd.global.config.whatsappTemplate_Failed;
  const calls: any[] = [];
  const s = await sendPaymentOutcomeNotification({ db: fakeDb(sd), fetchImpl: okFetch(calls), logger: silent }, "Failed", "tx-1");
  assert.equal(s.reason, "whatsappTemplate_Failed missing"); assert.equal(calls.length, 0);
});
test("resendTemplateLog routes failed logs to payments record", async () => {
  const db = fakeDb(failedSeed()); const calls: any[] = [];
  await sendPaymentOutcomeNotification({ db, fetchImpl: okFetch(calls), logger: silent }, "Failed", "tx-1");
  const log: any = Object.values(db.store.notification_logs)[0];
  const s = await resendTemplateLog({ db, fetchImpl: okFetch(calls), logger: silent }, log);
  assert.equal(s.accepted, 1); assert.equal(calls.length, 3);
});
