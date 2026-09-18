/**
 * PesaPal API 3.0 client — inatumika NA Edge Functions pekee (Deno).
 * ---------------------------------------------------------------------------
 * Hii ni module ya _shared: create-pesapal-order, pesapal-ipn,
 * pesapal-return na register-pesapal-ipn zote zina-import hapa.
 *
 * MUHIMU: consumer_key / consumer_secret ZINASOMWA kutoka Supabase
 * Edge Function secrets (Deno.env) — HAZIWEKWI kwenye code, hazipo
 * kwenye Flutter, hazipo kwenye git repo.
 *
 * Base URL (production): https://pay.pesapal.com/v3/api
 * Sandbox/test:          https://cybqa.pesapal.com/pesapalv3/api
 */

export const PESAPAL_BASE_URL: string = (
  Deno.env.get("PESAPAL_BASE_URL") ??
    "https://pay.pesapal.com/v3/api"
).replace(/\/+$/, "");

/** PesaPal token inaisha baada ya dakika 5 — tuna-cache kwa dakika 4. */
const TOKEN_CACHE_MS = 4 * 60 * 1000;

let cachedToken: { token: string; expiresAt: number } | null = null;

/** CORS headers — zinaruhusu Flutter client kuita functions hizi. */
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

export interface PesapalCredentials {
  consumerKey: string;
  consumerSecret: string;
}

/** Soma credentials kutoka Supabase secrets (kama hazipo -> error ya wazi). */
export function pesapalCredentials(): PesapalCredentials {
  const consumerKey = (Deno.env.get("PESAPAL_CONSUMER_KEY") ?? "").trim();
  const consumerSecret = (Deno.env.get("PESAPAL_CONSUMER_SECRET") ?? "").trim();

  if (!consumerKey || !consumerSecret) {
    throw new Error(
      "PESAPAL_CONSUMER_KEY / PESAPAL_CONSUMER_SECRET hazijawekwa. " +
        "Run: supabase secrets set PESAPAL_CONSUMER_KEY=... PESAPAL_CONSUMER_SECRET=...",
    );
  }

  return { consumerKey, consumerSecret };
}

/** ipn_id ya PesaPal (inarudishwa na register-pesapal-ipn). */
export function pesapalIpnId(): string {
  const ipnId = (Deno.env.get("PESAPAL_IPN_ID") ?? "").trim();

  if (!ipnId) {
    throw new Error(
      "PESAPAL_IPN_ID haijawekwa. Kwanza deploy register-pesapal-ipn, " +
        "iite mara moja kupata ipn_id, kisha: supabase secrets set PESAPAL_IPN_ID=<ipn_id>",
    );
  }

  return ipnId;
}

export function supabaseUrl(): string {
  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  if (!url) throw new Error("SUPABASE_URL haipo kwenye environment ya function.");
  return url;
}

export function serviceRoleKey(): string {
  const key = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY haipo kwenye environment ya function.");
  }
  return key;
}

// deno-lint-ignore no-explicit-any
async function asJson(res: Response): Promise<any> {
  const text = await res.text().catch(() => "");
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

// ---------------------------------------------------------------------------
// 1) Auth — POST /Auth/RequestToken
// ---------------------------------------------------------------------------
interface TokenResponse {
  token?: string;
  expiryDate?: string;
  error?: { error_type?: string; code?: string; message?: string } | null;
  status?: string;
}

/**
 * Rudisha bearer token. Inacache token kwa dakika 4 (token inaisha dakika 5)
 * ili kila order/status check isifanye RequestToken mpya.
 */
export async function getToken(
  consumerKey: string,
  consumerSecret: string,
): Promise<string> {
  if (cachedToken && Date.now() < cachedToken.expiresAt) {
    return cachedToken.token;
  }

  const res = await fetch(`${PESAPAL_BASE_URL}/Auth/RequestToken`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      consumer_key: consumerKey,
      consumer_secret: consumerSecret,
    }),
  });

  const data = (await asJson(res)) as TokenResponse | null;

  if (!res.ok || !data?.token) {
    throw new Error(
      `PesaPal RequestToken failed (${res.status}): ${JSON.stringify(data)}`,
    );
  }

  cachedToken = { token: data.token, expiresAt: Date.now() + TOKEN_CACHE_MS };
  return data.token;
}

/** Token cache inaweza kufutwa (mfano PesaPal ikirudisha 401). */
export function clearTokenCache(): void {
  cachedToken = null;
}

// ---------------------------------------------------------------------------
// 2) IPN registration — POST /URLSetup/RegisterIPN
// ---------------------------------------------------------------------------
export interface IpnRegistration {
  ipn_id?: string;
  url?: string;
  ipn_url?: string;
  ipn_notification_type?: string;
  created_date?: string;
  error?: { error_type?: string; code?: string; message?: string } | null;
  status?: string;
}

export async function registerIPN(
  token: string,
  url: string,
  ipnNotificationType: "GET" | "POST" = "GET",
): Promise<IpnRegistration> {
  const res = await fetch(`${PESAPAL_BASE_URL}/URLSetup/RegisterIPN`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ url, ipn_notification_type: ipnNotificationType }),
  });

  const data = (await asJson(res)) as IpnRegistration | null;

  if (!res.ok || !data?.ipn_id) {
    throw new Error(
      `PesaPal RegisterIPN failed (${res.status}): ${JSON.stringify(data)}`,
    );
  }

  return data;
}

/** GET /URLSetup/GetIpnList — kutafuta IPN iliyokwisha sajiliwa (kuepuka duplicates). */
export async function getIpnList(token: string): Promise<IpnRegistration[]> {
  const res = await fetch(`${PESAPAL_BASE_URL}/URLSetup/GetIpnList`, {
    method: "GET",
    headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
  });

  const data = await asJson(res);
  if (!res.ok || !Array.isArray(data)) return [];
  return data as IpnRegistration[];
}

// ---------------------------------------------------------------------------
// 3) Submit order — POST /Transactions/SubmitOrderRequest
// ---------------------------------------------------------------------------
export interface PesapalBillingAddress {
  email_address: string;
  phone_number?: string;
  country_code?: string;
  first_name?: string;
  last_name?: string;
  middle_name?: string;
  line_1?: string;
  line_2?: string;
  city?: string;
  state?: string;
  postal_code?: string;
  zip_code?: string;
}

export interface SubmitOrderPayload {
  /** Merchant reference / order id — LAZIMA iwe unique. */
  id: string;
  currency: string;
  amount: number;
  description: string;
  /** URL ya kurudi baada ya malipo (callback_url). */
  callback_url: string;
  /** ipn_id iliyosajiliwa (PESAPAL_IPN_ID). */
  notification_id: string;
  billing_address: PesapalBillingAddress;
  branch?: string;
}

export interface SubmitOrderResult {
  order_tracking_id?: string;
  merchant_reference?: string;
  redirect_url?: string;
  error?: { error_type?: string; code?: string; message?: string } | null;
  status?: string;
}

export async function submitOrder(
  token: string,
  payload: SubmitOrderPayload,
): Promise<SubmitOrderResult> {
  const res = await fetch(
    `${PESAPAL_BASE_URL}/Transactions/SubmitOrderRequest`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    },
  );

  const data = (await asJson(res)) as SubmitOrderResult | null;

  if (!res.ok || data?.error) {
    throw new Error(
      `PesaPal SubmitOrderRequest failed (${res.status}): ${JSON.stringify(data)}`,
    );
  }

  return data ?? {};
}

// ---------------------------------------------------------------------------
// 4) Transaction status — GET /Transactions/GetTransactionStatus
// ---------------------------------------------------------------------------
export interface PesapalTransactionStatus {
  payment_method?: string;
  amount?: number;
  created_date?: string;
  confirmation_code?: string;
  payment_status_description?: string;
  description?: string;
  message?: string;
  payment_account?: string;
  call_back_url?: string;
  /** 0 = INVALID, 1 = COMPLETED, 2 = FAILED, 3 = REVERSED */
  status_code?: number;
  merchant_reference?: string;
  payment_status?: string;
  currency?: string;
  error?: { error_type?: string; code?: string; message?: string } | null;
  status?: string;
}

export async function getTransactionStatus(
  token: string,
  orderTrackingId: string,
): Promise<PesapalTransactionStatus> {
  const url = `${PESAPAL_BASE_URL}/Transactions/GetTransactionStatus?orderTrackingId=${
    encodeURIComponent(orderTrackingId)
  }`;

  const res = await fetch(url, {
    method: "GET",
    headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
  });

  const data = (await asJson(res)) as PesapalTransactionStatus | null;

  if (!res.ok || data?.error) {
    throw new Error(
      `PesaPal GetTransactionStatus failed (${res.status}): ${JSON.stringify(data)}`,
    );
  }

  return data ?? {};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export type PaymentDbStatus = "PENDING" | "COMPLETED" | "FAILED";

/** Badilisha PesaPal status_code -> status ya jedwali la transactions. */
export function mapStatusCodeToDbStatus(
  statusCode?: number,
  description?: string,
): PaymentDbStatus {
  if (statusCode === 1) return "COMPLETED";
  if (statusCode === 2 || statusCode === 3) return "FAILED";

  const text = (description ?? "").toLowerCase();
  if (text.includes("completed") || text.includes("success")) {
    return "COMPLETED";
  }
  if (
    text.includes("fail") || text.includes("invalid") ||
    text.includes("reversed") || text.includes("cancelled")
  ) {
    return "FAILED";
  }

  // status_code 0 (INVALID) na kila kitu kingine = bado PENDING.
  return "PENDING";
}

/** Tengeneze order id: "PACIFIC-<uid>-<timestamp>" (punguza urefu ikihitajika). */
export function buildOrderId(uid: string, now: number = Date.now()): string {
  const full = `PACIFIC-${uid}-${now}`;
  // Merchant reference ya PesaPal: hifadhi chini ya chars 50.
  return full.length <= 50 ? full : `PACIFIC-${uid.slice(0, 8)}-${now}`;
}