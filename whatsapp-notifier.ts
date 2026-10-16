// ---------------------------------------------------------------------------
// WhatsApp transactional notifications (server-side only).
//
// - All configuration is read at send time from Firestore `global/config`
//   (single source of truth). Nothing is hardcoded; no in-memory fallback.
// - "Order Placed" uses the approved Meta template named in
//   `global/config.whatsappTemplateOrderPlaced`.
// - Recipients: sales_orders.customerMobile (resolved to international format
//   via `customer_mobile_plus_code_index`) + global/config.successPhones1/2
//   (Success) or failedPhones1/2 (Failed / Cancelled).
// - Deduplication: one `notification_logs` doc per deterministic eventKey
//   (orderId + stage + recipient). Repeats/retries never resend an accepted msg.
// - Provider acceptance is NOT delivery; logs record `deliveryStatus:'Accepted'`.
// - Tokens / auth headers are never logged or returned.
// ---------------------------------------------------------------------------
import crypto from "crypto";

export type NotificationOutcome = "Success" | "Failed" | "Cancelled";
export type NotificationStage = "OrderPlaced" | "PaymentFailed" | "PaymentCancelled";

export const GLOBAL_CONFIG = { collection: "global", doc: "config" } as const;
export const LOG_COLLECTION = "notification_logs";
export const PLUS_CODE_INDEX = "customer_mobile_plus_code_index";
export const DEFAULT_TEMPLATE_LANGUAGE = "en_US";

/**
 * Body-parameter order for the approved Order Placed template
 * (leafyearth_orderconfirm, en_US):
 *   {{1}} customer name  -> "Hi {{1}},"
 *   {{2}} purchase word  -> "Thank you for your {{2}}!"
 *   {{3}} order number   -> "Your order #{{3}} ..."  (template already prints '#')
 *   {{4}} items          -> "getting your {{4}} ready"
 *   {{5}} est. delivery  -> "Estimated Delivery: {{5}}"
 */
export const ORDER_PLACED_PARAM_ORDER = [
  "customerName",
  "purchaseWord",
  "orderNumber",
  "items",
  "estimatedDelivery",
] as const;
export const ORDER_PLACED_PURCHASE_WORD = "purchase";
export const ESTIMATED_DELIVERY_FALLBACK = "Will be shared on dispatch";

/** Body-parameter order for the Failed/Cancelled template (whatsappTemplate_Failed). */
export const PAYMENT_OUTCOME_PARAM_ORDER = [
  "customerName",
  "orderNumber",
  "orderDate",
  "items",
  "deliveryAddress",
] as const;

const MAX_PARAM_LEN = 1000;
const REQUEST_TIMEOUT_MS = 10_000;
const MAX_ATTEMPTS = 3;
const STALE_PENDING_MS = 5 * 60_000;

export interface Logger {
  info: (...a: any[]) => void;
  warn: (...a: any[]) => void;
  error: (...a: any[]) => void;
}
const defaultLogger: Logger = console;

// ----------------------------- Configuration ------------------------------

export interface WhatsAppConfig {
  endpoint: string;
  token: string;
  phoneId: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; reason: string };

export async function readGlobalConfig(db: any): Promise<Record<string, any> | null> {
  const snap = await db.collection(GLOBAL_CONFIG.collection).doc(GLOBAL_CONFIG.doc).get();
  return snap.exists ? (snap.data() || {}) : null;
}

/** Validates whatsappPhoneId / whatsappToken / whatsappApiUrl and builds the /messages endpoint. */
export function validateWhatsAppConfig(cfg: Record<string, any> | null | undefined): Result<WhatsAppConfig> {
  if (!cfg) return { ok: false, reason: "global/config not found" };
  const token = typeof cfg.whatsappToken === "string" ? cfg.whatsappToken.trim() : "";
  const phoneId = typeof cfg.whatsappPhoneId === "string" || typeof cfg.whatsappPhoneId === "number"
    ? String(cfg.whatsappPhoneId).trim() : "";
  const rawUrl = typeof cfg.whatsappApiUrl === "string" ? cfg.whatsappApiUrl.trim() : "";

  if (!token) return { ok: false, reason: "whatsappToken missing" };
  if (!/^\d{5,30}$/.test(phoneId)) return { ok: false, reason: "whatsappPhoneId missing or malformed" };
  if (!rawUrl) return { ok: false, reason: "whatsappApiUrl missing" };

  let url: URL;
  try { url = new URL(rawUrl); } catch { return { ok: false, reason: "whatsappApiUrl malformed" }; }
  if (url.protocol !== "https:") return { ok: false, reason: "whatsappApiUrl must use https" };

  const base = url.toString().replace(/\/+$/, "");
  let endpoint: string;
  if (/\/messages$/.test(base)) endpoint = base;                       // full endpoint stored
  else if (base.endsWith(`/${phoneId}`)) endpoint = `${base}/messages`; // base + phone id stored
  else endpoint = `${base}/${phoneId}/messages`;                        // base (e.g. .../v17.0) stored
  return { ok: true, value: { endpoint, token, phoneId } };
}

/** Meta template names: lowercase letters, digits and underscores. */
export function validateTemplateName(v: unknown, field = "whatsappTemplateOrderPlaced"): Result<string> {
  const name = typeof v === "string" ? v.trim() : "";
  if (!name) return { ok: false, reason: `${field} missing` };
  if (!/^[a-z0-9_]{1,512}$/.test(name)) return { ok: false, reason: `${field} malformed` };
  return { ok: true, value: name };
}

export function resolveTemplateLanguage(cfg: Record<string, any>): string {
  const v = typeof cfg?.whatsappTemplateLanguage === "string" ? cfg.whatsappTemplateLanguage.trim() : "";
  return /^[a-z]{2,3}(_[A-Z]{2})?$/.test(v) ? v : DEFAULT_TEMPLATE_LANGUAGE;
}

/** Meta error: template name does not exist in the requested translation (language). */
export const META_TEMPLATE_LANG_MISSING = 132001;

/** Ordered, de-duplicated language codes to try (primary first, then config/common fallbacks). */
export function templateLanguageCandidates(primary: string, cfg: Record<string, any>): string[] {
  const fromCfg = [cfg?.whatsappTemplateLanguage, cfg?.whatsappTemplateLanguage]
    .map(v => (typeof v === "string" ? v.trim() : ""))
    .filter(v => /^[a-z]{2,3}(_[A-Z]{2})?$/.test(v));
  return [...new Set([primary, ...fromCfg, "en", "en_US", "en_GB"])];
}

// ------------------------------ Recipients --------------------------------

export function recipientFieldsFor(outcome: NotificationOutcome): string[] {
  return outcome === "Success" ? ["successPhones1", "successPhones2"] : ["failedPhones1", "failedPhones2"];
}

/** Accepts a string (optionally comma/semicolon separated) or array of strings. */
export function extractPhoneValues(v: unknown): string[] {
  if (Array.isArray(v)) return v.flatMap(extractPhoneValues);
  if (typeof v === "number") return [String(v)];
  if (typeof v !== "string") return [];
  return v.split(/[,;]/).map(s => s.trim()).filter(Boolean);
}

/**
 * Normalizes to Cloud API digits-only international form.
 * - "+<cc><number>" / "00<cc><number>" -> digits (8..15)
 * - bare 10-digit national numbers -> "needs_country_code" (never guessed here)
 */
export function normalizeInternational(raw: string): Result<string> | { ok: false; reason: "needs_country_code"; national: string } {
  const s = String(raw || "").trim();
  if (!s) return { ok: false, reason: "empty" };
  if (/[a-zA-Z@]/.test(s)) return { ok: false, reason: "not_a_phone_number" };
  const digits = s.replace(/\D/g, "");
  if (s.startsWith("+")) {
    return digits.length >= 8 && digits.length <= 15 ? { ok: true, value: digits } : { ok: false, reason: "invalid_length" };
  }
  if (digits.startsWith("00")) {
    const d = digits.slice(2);
    return d.length >= 8 && d.length <= 15 ? { ok: true, value: d } : { ok: false, reason: "invalid_length" };
  }
  if (digits.length === 10) return { ok: false, reason: "needs_country_code", national: digits };
  return { ok: false, reason: "missing_country_code_or_invalid" };
}

export function maskPhone(digits: string): string {
  const d = String(digits || "").replace(/\D/g, "");
  return d.length <= 4 ? "****" : `${"*".repeat(d.length - 4)}${d.slice(-4)}`;
}

export interface ResolvedRecipient { digits: string; source: string }
export interface SkippedRecipient { masked: string; source: string; reason: string }

/** Resolves a 10-digit customerMobile via customer_mobile_plus_code_index (+91 confirmed by index). */
export async function resolveCustomerMobile(db: any, customerMobile: unknown): Promise<Result<string>> {
  const raw = typeof customerMobile === "string" || typeof customerMobile === "number" ? String(customerMobile) : "";
  const norm = normalizeInternational(raw);
  if (norm.ok) return norm;
  if ((norm as any).reason !== "needs_country_code") return { ok: false, reason: norm.reason };
  const plusCode = `+91${(norm as any).national}`;
  const idx = await db.collection(PLUS_CODE_INDEX).doc(plusCode).get();
  if (!idx.exists) return { ok: false, reason: "not_found_in_customer_mobile_plus_code_index" };
  const stored = String(idx.data()?.mobileNumberpluscode || plusCode);
  const confirmed = normalizeInternational(stored);
  return confirmed.ok ? confirmed : { ok: false, reason: "index_entry_malformed" };
}

export async function resolveRecipients(
  db: any, outcome: NotificationOutcome, order: any, cfg: Record<string, any>
): Promise<{ recipients: ResolvedRecipient[]; skipped: SkippedRecipient[] }> {
  const recipients: ResolvedRecipient[] = [];
  const skipped: SkippedRecipient[] = [];
  const seen = new Set<string>();
  const add = (digits: string, source: string) => {
    if (seen.has(digits)) { skipped.push({ masked: maskPhone(digits), source, reason: "duplicate_recipient" }); return; }
    seen.add(digits);
    recipients.push({ digits, source });
  };

  const cust = await resolveCustomerMobile(db, order?.customerMobile);
  if (cust.ok) add(cust.value, "customerMobile");
  else skipped.push({ masked: maskPhone(String(order?.customerMobile || "")), source: "customerMobile", reason: cust.reason });

  for (const field of recipientFieldsFor(outcome)) {
    for (const raw of extractPhoneValues(cfg?.[field])) {
      const n = normalizeInternational(raw);
      if (n.ok) add(n.value, field);
      else skipped.push({ masked: maskPhone(raw), source: field, reason: n.reason });
    }
  }
  return { recipients, skipped };
}

// ------------------------------ Parameters --------------------------------

/** Meta rejects params containing newlines, tabs or >4 consecutive spaces. */
export function sanitizeParam(v: unknown, fallback = "-"): string {
  const s = String(v ?? "").replace(/[\r\n\t]+/g, " ").replace(/ {2,}/g, " ").trim();
  if (!s) return fallback;
  return s.length > MAX_PARAM_LEN ? `${s.slice(0, MAX_PARAM_LEN - 3)}...` : s;
}

export function formatOrderDate(v: unknown): string {
  const d = v ? new Date(String(v)) : null;
  if (!d || isNaN(d.getTime())) return "";
  return d.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });
}

export function formatItems(products: any[]): string {
  if (!Array.isArray(products)) return "";
  return products.map(p => {
    const name = p?.productName || p?.name || "";
    if (!name) return "";
    const sku = p?.sku ? ` (SKU ${p.sku})` : "";
    const qty = p?.quantity != null ? ` x ${p.quantity}` : "";
    return `${name}${sku}${qty}`;
  }).filter(Boolean).join(", ");
}

export function formatAddress(addr: any): string {
  if (!addr || typeof addr !== "object") return "";
  const parts = [
    addr.addressLine, addr.addressLine1, addr.addressLine2, addr.locality, addr.area,
    addr.city, addr.district, addr.state,
  ].map(x => (typeof x === "string" ? x.trim() : "")).filter(Boolean);
  const unique = parts.filter((p, i) => parts.indexOf(p) === i).join(", ");
  return addr.pincode ? `${unique}${unique ? " - " : ""}${addr.pincode}` : unique;
}

export function buildOrderPlacedParams(order: any): string[] {
  const addr = order?.shippingAddress || order?.deliveryAddress || {};
  const eddRaw = order?.estimatedDelivery || order?.estimatedDeliveryDate || order?.expectedDeliveryDate;
  const values: Record<(typeof ORDER_PLACED_PARAM_ORDER)[number], string> = {
    customerName: order?.customerName || addr?.name || "Customer",
    purchaseWord: ORDER_PLACED_PURCHASE_WORD,
    orderNumber: String(order?.orderNumber || order?.id || "").replace(/^#+/, ""),
    items: formatItems(order?.products || []),
    estimatedDelivery: (eddRaw && formatOrderDate(eddRaw)) || ESTIMATED_DELIVERY_FALLBACK,
  };
  return ORDER_PLACED_PARAM_ORDER.map(k => sanitizeParam(values[k]));
}

export function buildPaymentOutcomeParams(order: any): string[] {
  const addr = order?.shippingAddress || order?.deliveryAddress || {};
  const values: Record<(typeof PAYMENT_OUTCOME_PARAM_ORDER)[number], string> = {
    customerName: order?.customerName || addr?.name || "",
    orderNumber: order?.orderNumber || order?.id || "",
    orderDate: formatOrderDate(order?.createdAt || order?.orderDate),
    items: formatItems(order?.products || []),
    deliveryAddress: formatAddress(addr),
  };
  return PAYMENT_OUTCOME_PARAM_ORDER.map(k => sanitizeParam(values[k]));
}

export function buildTemplatePayload(to: string, templateName: string, language: string, params: string[]) {
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: "template",
    template: {
      name: templateName,
      language: { code: language },
      components: [{ type: "body", parameters: params.map(text => ({ type: "text", text })) }],
    },
  };
}

// ----------------------------- Deduplication ------------------------------

export function buildEventKey(orderId: string, stage: NotificationStage, digits: string): string {
  const recipientHash = crypto.createHash("sha256").update(String(digits)).digest("hex").slice(0, 16);
  return `wa:${orderId}:${stage}:${recipientHash}`;
}
export function eventLogId(eventKey: string): string {
  return `wa-${crypto.createHash("sha256").update(eventKey).digest("hex").slice(0, 40)}`;
}

/** Atomically claims an eventKey. Returns false when already accepted or in flight. */
export async function claimEvent(db: any, eventKey: string, base: Record<string, any>, force = false): Promise<boolean> {
  const ref = db.collection(LOG_COLLECTION).doc(eventLogId(eventKey));
  return db.runTransaction(async (t: any) => {
    const snap = await t.get(ref);
    if (snap.exists && !force) {
      const d = snap.data() || {};
      if (d.status === "Success") return false;
      if (d.status === "Pending" && Date.now() - Date.parse(d.dateTime || 0) < STALE_PENDING_MS) return false;
      if (d.status === "Failed" && d.permanentFailure) return false;
    }
    t.set(ref, { ...base, id: ref.id, eventKey, status: "Pending", dateTime: new Date().toISOString() }, { merge: true });
    return true;
  });
}

// -------------------------------- Sender ----------------------------------

export interface SendResult {
  ok: boolean;
  messageId?: string;
  httpStatus?: number;
  errorCode?: string | number;
  errorMessage?: string;
  transient?: boolean;
  attempts: number;
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

export async function postWithRetry(
  fetchImpl: typeof fetch, endpoint: string, token: string, body: any,
  opts: { timeoutMs?: number; maxAttempts?: number; backoffMs?: number } = {}
): Promise<SendResult> {
  const timeoutMs = opts.timeoutMs ?? REQUEST_TIMEOUT_MS;
  const maxAttempts = opts.maxAttempts ?? MAX_ATTEMPTS;
  const backoffMs = opts.backoffMs ?? 500;
  let last: SendResult = { ok: false, attempts: 0, errorMessage: "not attempted" };

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
      let data: any = {};
      try { data = await res.json(); } catch { /* non-JSON body */ }
      if (res.ok) {
        return { ok: true, messageId: data?.messages?.[0]?.id, httpStatus: res.status, attempts: attempt };
      }
      const transient = res.status === 429 || res.status >= 500;
      last = {
        ok: false, httpStatus: res.status, transient, attempts: attempt,
        errorCode: data?.error?.code,
        errorMessage: sanitizeParam(data?.error?.message || `HTTP ${res.status}`, `HTTP ${res.status}`).slice(0, 300),
      };
      if (!transient) return last;
    } catch (err: any) {
      last = {
        ok: false, transient: true, attempts: attempt,
        errorMessage: err?.name === "AbortError" ? "request timeout" : "network error",
      };
    } finally {
      clearTimeout(timer);
    }
    if (attempt < maxAttempts) await sleep(backoffMs * 2 ** (attempt - 1));
  }
  return last;
}

// ----------------------------- Orchestration ------------------------------

export interface NotifyDeps { db: any; fetchImpl?: typeof fetch; logger?: Logger }
export interface NotifySummary {
  status: "sent" | "partial" | "failed" | "skipped";
  reason?: string;
  accepted: number;
  failed: number;
  duplicates: number;
  skipped: SkippedRecipient[];
}

type TemplateField = "whatsappTemplateOrderPlaced" | "whatsappTemplate_Failed";
interface SendSpec {
  stage: NotificationStage;
  outcome: NotificationOutcome;
  templateField: TemplateField;
  /** Loads the latest trusted record from Firestore; returns null when missing. */
  load: (db: any) => Promise<{ orderId: string; paymentId?: string; data: any } | null>;
}

export const TEMPLATE_FIELD_FOR: Record<NotificationOutcome, TemplateField> = {
  Success: "whatsappTemplateOrderPlaced",
  Failed: "whatsappTemplate_Failed",
  Cancelled: "whatsappTemplate_Failed",
};
export const STAGE_FOR: Record<NotificationOutcome, NotificationStage> = {
  Success: "OrderPlaced",
  Failed: "PaymentFailed",
  Cancelled: "PaymentCancelled",
};

async function sendTemplateNotification(
  deps: NotifyDeps, spec: SendSpec, opts: { onlyEventKey?: string; force?: boolean }
): Promise<NotifySummary> {
  const log = deps.logger || defaultLogger;
  const fetchImpl = deps.fetchImpl || fetch;
  const empty = (reason: string): NotifySummary => ({ status: "skipped", reason, accepted: 0, failed: 0, duplicates: 0, skipped: [] });
  const tag = `[WhatsApp ${spec.stage}]`;

  try {
    let cfg: Record<string, any> | null;
    try { cfg = await readGlobalConfig(deps.db); }
    catch { log.error(`${tag} skipped: global/config unreadable`); return empty("global/config unreadable"); }

    const waCfg = validateWhatsAppConfig(cfg);
    if (!waCfg.ok) { log.warn(`${tag} skipped: ${waCfg.reason}`); return empty(waCfg.reason); }
    const tpl = validateTemplateName(cfg![spec.templateField], spec.templateField);
    if (!tpl.ok) { log.warn(`${tag} skipped: ${tpl.reason}`); return empty(tpl.reason); }
    const language = resolveTemplateLanguage(cfg!);

    const record = await spec.load(deps.db);
    if (!record) { log.warn(`${tag} skipped: record not found`); return empty("record not found"); }
    const order = record.data;

    const { recipients, skipped } = await resolveRecipients(deps.db, spec.outcome, order, cfg!);
    for (const s of skipped) log.warn(`${tag} recipient skipped (${s.source} ${s.masked}): ${s.reason}`);
    if (recipients.length === 0) return { ...empty("no valid recipients"), skipped };

    const params = spec.stage === "OrderPlaced" ? buildOrderPlacedParams(order) : buildPaymentOutcomeParams(order);
    const summary: NotifySummary = { status: "sent", accepted: 0, failed: 0, duplicates: 0, skipped };

    for (const r of recipients) {
      const eventKey = buildEventKey(record.orderId, spec.stage, r.digits);
      if (opts.onlyEventKey && opts.onlyEventKey !== eventKey) continue;

      const base = {
        ...(record.paymentId ? { paymentId: record.paymentId } : {}),
        type: "WhatsApp",
        stage: spec.stage,
        paymentStatus: spec.outcome,
        orderId: record.orderId,
        orderNumber: order.orderNumber || record.orderId,
        recipient: maskPhone(r.digits),
        recipientSource: r.source,
        templateName: tpl.value,
        templateLanguage: language,
      };
      const claimed = await claimEvent(deps.db, eventKey, base, !!opts.force);
      if (!claimed) { summary.duplicates++; log.info(`${tag} duplicate event skipped for ${base.recipient}`); continue; }

      let usedLanguage = language;
      let result = await postWithRetry(fetchImpl, waCfg.value.endpoint, waCfg.value.token,
        buildTemplatePayload(r.digits, tpl.value, language, params));
      if (!result.ok && Number(result.errorCode) === META_TEMPLATE_LANG_MISSING) {
        for (const alt of templateLanguageCandidates(language, cfg!).slice(1)) {
          log.warn(`${tag} template ${tpl.value} not found in ${usedLanguage}; retrying with ${alt}`);
          usedLanguage = alt;
          result = await postWithRetry(fetchImpl, waCfg.value.endpoint, waCfg.value.token,
            buildTemplatePayload(r.digits, tpl.value, alt, params));
          if (result.ok || Number(result.errorCode) !== META_TEMPLATE_LANG_MISSING) break;
        }
      }

      await deps.db.collection(LOG_COLLECTION).doc(eventLogId(eventKey)).set({
        status: result.ok ? "Success" : "Failed",
        deliveryStatus: result.ok ? "Accepted" : "Not Sent",
        providerMessageId: result.messageId || "",
        errorMessage: result.ok ? "" : (result.errorMessage || "WhatsApp send failed"),
        errorCode: result.errorCode ?? "",
        httpStatus: result.httpStatus ?? null,
        permanentFailure: !result.ok && !result.transient,
        attempts: result.attempts,
        templateLanguage: usedLanguage,
        dateTime: new Date().toISOString(),
      }, { merge: true });

      if (result.ok) { summary.accepted++; log.info(`${tag} accepted by provider for ${base.recipient}`); }
      else { summary.failed++; log.error(`${tag} send failed for ${base.recipient}: ${result.errorMessage}`); }
    }

    summary.status = summary.failed === 0
      ? (summary.accepted > 0 ? "sent" : "skipped")
      : (summary.accepted > 0 ? "partial" : "failed");
    if (summary.status === "skipped" && summary.duplicates > 0) summary.reason = "duplicate event";
    return summary;
  } catch (err: any) {
    log.error(`${tag} unexpected error: ${err?.message || "unknown"}`);
    return empty("unexpected error");
  }
}

/**
 * Order Placed template (global/config.whatsappTemplateOrderPlaced) for a persisted
 * sales order. Never throws; never mutates sales_orders. Call only after the save.
 * `onlyEventKey` + `force` are used by the admin resend path.
 */
export async function sendOrderPlacedNotification(
  deps: NotifyDeps, orderId: string, opts: { onlyEventKey?: string; force?: boolean } = {}
): Promise<NotifySummary> {
  if (!orderId) return { status: "skipped", reason: "missing orderId", accepted: 0, failed: 0, duplicates: 0, skipped: [] };
  return sendTemplateNotification(deps, {
    stage: "OrderPlaced", outcome: "Success", templateField: "whatsappTemplateOrderPlaced",
    load: async (db) => {
      const snap = await db.collection("sales_orders").doc(String(orderId)).get();
      return snap.exists ? { orderId: snap.id, data: { id: snap.id, ...snap.data() } } : null;
    },
  }, opts);
}

/**
 * Failed / Cancelled template (global/config.whatsappTemplate_Failed). No sales order
 * exists for an unpaid checkout, so data comes from the persisted `payments` record
 * (its server-stored orderPayload). Call only after the payment status is saved.
 */
export async function sendPaymentOutcomeNotification(
  deps: NotifyDeps, outcome: "Failed" | "Cancelled", paymentId: string,
  opts: { onlyEventKey?: string; force?: boolean } = {}
): Promise<NotifySummary> {
  if (!paymentId) return { status: "skipped", reason: "missing paymentId", accepted: 0, failed: 0, duplicates: 0, skipped: [] };
  return sendTemplateNotification(deps, {
    stage: STAGE_FOR[outcome], outcome, templateField: TEMPLATE_FIELD_FOR[outcome],
    load: async (db) => {
      const snap = await db.collection("payments").doc(String(paymentId)).get();
      if (!snap.exists) return null;
      const tx = snap.data() || {};
      const payload = tx.orderPayload || {};
      const orderId = String(tx.orderId || snap.id);
      return {
        orderId,
        paymentId: snap.id,
        data: { ...payload, id: orderId, orderNumber: payload.orderNumber || orderId, createdAt: payload.createdAt || tx.createdAt },
      };
    },
  }, opts);
}

/** Admin resend for any template-based WhatsApp log. */
export async function resendTemplateLog(deps: NotifyDeps, log: any): Promise<NotifySummary> {
  const opts = { onlyEventKey: String(log.eventKey), force: true };
  if (log.stage === "PaymentFailed" || log.stage === "PaymentCancelled") {
    return sendPaymentOutcomeNotification(deps, log.stage === "PaymentFailed" ? "Failed" : "Cancelled",
      String(log.paymentId || log.orderId), opts);
  }
  return sendOrderPlacedNotification(deps, String(log.orderId), opts);
}

// ------------------------------ Lead Added --------------------------------

export const LEAD_ADD_TEMPLATE_FIELD = "whatsappTemplateleadadd";
/** Language of the lead-add template (global/config.whatsappTemplateLanguage), e.g. "en". */
export const LEAD_ADD_LANGUAGE_FIELD = "whatsappTemplateLanguage";

export function resolveLeadTemplateLanguage(cfg: Record<string, any>): string {
  const v = typeof cfg?.[LEAD_ADD_LANGUAGE_FIELD] === "string" ? cfg[LEAD_ADD_LANGUAGE_FIELD].trim() : "";
  return /^[a-z]{2,3}(_[A-Z]{2})?$/.test(v) ? v : resolveTemplateLanguage(cfg);
}
/** Meta error code for template parameter-count mismatch. */
const META_PARAM_MISMATCH = 132000;

/**
 * Welcome template (global/config.whatsappTemplateleadadd) sent to a newly saved lead's
 * WhatsApp mobile. Body param {{1}} = lead name; if the approved template has no body
 * variables, it automatically retries without params. Never throws. Deduped per lead.
 */
export async function sendLeadAddedNotification(deps: NotifyDeps, leadId: string): Promise<NotifySummary> {
  const log = deps.logger || defaultLogger;
  const fetchImpl = deps.fetchImpl || fetch;
  const tag = "[WhatsApp LeadAdded]";
  const empty = (reason: string): NotifySummary => ({ status: "skipped", reason, accepted: 0, failed: 0, duplicates: 0, skipped: [] });
  try {
    if (!leadId) return empty("missing leadId");
    let cfg: Record<string, any> | null;
    try { cfg = await readGlobalConfig(deps.db); }
    catch { log.error(`${tag} skipped: global/config unreadable`); return empty("global/config unreadable"); }
    const waCfg = validateWhatsAppConfig(cfg);
    if (!waCfg.ok) { log.warn(`${tag} skipped: ${waCfg.reason}`); return empty(waCfg.reason); }
    const tpl = validateTemplateName(cfg![LEAD_ADD_TEMPLATE_FIELD], LEAD_ADD_TEMPLATE_FIELD);
    if (!tpl.ok) { log.warn(`${tag} skipped: ${tpl.reason}`); return empty(tpl.reason); }
    const language = resolveLeadTemplateLanguage(cfg!);

    const snap = await deps.db.collection("leads").doc(String(leadId)).get();
    if (!snap.exists) return empty("lead not found");
    const lead = snap.data() || {};
    const national = String(lead.phone || "").replace(/\D/g, "");
    const cc = String(lead.countrymobilecode || "+91").replace(/\D/g, "") || "91";
    const norm = normalizeInternational(String(lead.mobilenumberwithcountrycode || `+${cc}${national}`));
    if (!norm.ok) { log.warn(`${tag} skipped: invalid lead mobile (${norm.reason})`); return empty(`invalid lead mobile: ${norm.reason}`); }
    const digits = norm.value;

    const eventKey = `wa:lead:${leadId}:LeadAdded:${crypto.createHash("sha256").update(digits).digest("hex").slice(0, 16)}`;
    const base = {
      type: "WhatsApp", stage: "LeadAdded", leadId: String(leadId), orderId: String(leadId),
      recipient: maskPhone(digits), recipientSource: "lead.phone", templateName: tpl.value, templateLanguage: language,
    };
    if (!(await claimEvent(deps.db, eventKey, base))) {
      log.info(`${tag} duplicate event skipped for ${base.recipient}`);
      return { ...empty("duplicate event"), duplicates: 1 };
    }

    const name = sanitizeParam(lead.name || lead.contactName, "Customer");
    let result = await postWithRetry(fetchImpl, waCfg.value.endpoint, waCfg.value.token,
      buildTemplatePayload(digits, tpl.value, language, [name]));
    if (!result.ok && Number(result.errorCode) === META_PARAM_MISMATCH) {
      const noParams: any = buildTemplatePayload(digits, tpl.value, language, []);
      delete noParams.template.components;
      result = await postWithRetry(fetchImpl, waCfg.value.endpoint, waCfg.value.token, noParams);
    }

    await deps.db.collection(LOG_COLLECTION).doc(eventLogId(eventKey)).set({
      status: result.ok ? "Success" : "Failed",
      deliveryStatus: result.ok ? "Accepted" : "Not Sent",
      providerMessageId: result.messageId || "",
      errorMessage: result.ok ? "" : (result.errorMessage || "WhatsApp send failed"),
      errorCode: result.errorCode ?? "",
      httpStatus: result.httpStatus ?? null,
      permanentFailure: !result.ok && !result.transient,
      attempts: result.attempts,
      dateTime: new Date().toISOString(),
    }, { merge: true });

    if (result.ok) log.info(`${tag} accepted by provider for ${base.recipient}`);
    else log.error(`${tag} send failed for ${base.recipient}: ${result.errorMessage}`);
    return { status: result.ok ? "sent" : "failed", accepted: result.ok ? 1 : 0, failed: result.ok ? 0 : 1, duplicates: 0, skipped: [] };
  } catch (err: any) {
    log.error(`${tag} unexpected error: ${err?.message || "unknown"}`);
    return empty("unexpected error");
  }
}

