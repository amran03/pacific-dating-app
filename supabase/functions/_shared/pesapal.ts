/**
 * PesaPal API 3.0 client — used ONLY by Edge Functions (Deno).
 * ---------------------------------------------------------------------------
 * This is the _shared module: create-pesapal-order, pesapal-ipn,
 * pesapal-return and register-pesapal-ipn all import from here.
 *
 * IMPORTANT: consumer_key / consumer_secret are READ from Supabase
 * Edge Function secrets (Deno.env) — they are NOT hardcoded, they are not
 * in Flutter, and they are not in the git repo.
 *
 * Base URL (production): https://pay.pesapal.com/v3/api
 * Sandbox/test:          https://cybqa.pesapal.com/pesapalv3/api
 */

export const PESAPAL_BASE_URL: string = (
  Deno.env.get("PESAPAL_BASE_URL") ??
    "https://pay.pesapal.com/v3/api"
).replace(/\/+$/, "");

/** The PesaPal token expires after 5 minutes — we cache it for 4 minutes. */
const TOKEN_CACHE_MS = 4 * 60 * 1000;

let cachedToken: { token: string; expiresAt: number } | null = null;

/** CORS headers — they allow the Flutter client to call these functions. */
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

/** Read credentials from Supabase secrets (missing -> clear error). */
export function pesapalCredentials(): PesapalCredentials {
  const consumerKey = (Deno.env.get("PESAPAL_CONSUMER_KEY") ?? "").trim();
  const consumerSecret = (Deno.env.get("PESAPAL_CONSUMER_SECRET") ?? "").trim();

  if (!consumerKey || !consumerSecret) {
    throw new Error(
      "PESAPAL_CONSUMER_KEY / PESAPAL_CONSUMER_SECRET are not set. " +
        "Run: supabase secrets set PESAPAL_CONSUMER_KEY=... PESAPAL_CONSUMER_SECRET=...",
    );
  }

  return { consumerKey, consumerSecret };
}

/** The PesaPal ipn_id (returned by register-pesapal-ipn). */
export function pesapalIpnId(): string {
  const ipnId = (Deno.env.get("PESAPAL_IPN_ID") ?? "").trim();

  if (!ipnId) {
    throw new Error(
      "PESAPAL_IPN_ID is not set. First deploy register-pesapal-ipn, " +
        "call it once to get the ipn_id, then: supabase secrets set PESAPAL_IPN_ID=<ipn_id>",
    );
  }

  return ipnId;
}

export function supabaseUrl(): string {
  const url = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  if (!url) throw new Error("SUPABASE_URL is missing from the function environment.");
  return url;
}

export function serviceRoleKey(): string {
  const key = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is missing from the function environment.");
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
 * Return a bearer token. The token is cached for 4 minutes (it expires in
 * 5 minutes) so every order/status check doesn't request a new token.
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

/** The token cache can be cleared (e.g. when PesaPal returns 401). */
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

/** GET /URLSetup/GetIpnList — look up an already-registered IPN (avoids duplicates). */
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
  /** Merchant reference / order id — MUST be unique. */
  id: string;
  currency: string;
  amount: number;
  description: string;
  /** The URL to return to after payment (callback_url). */
  callback_url: string;
  /** The registered ipn_id (PESAPAL_IPN_ID). */
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

/** Map PesaPal status_code -> transactions table status. */
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

  // status_code 0 (INVALID) and anything else = still PENDING.
  return "PENDING";
}

/** Build the order id: "PACIFIC-<uid>-<timestamp>" (shortened if needed). */
export function buildOrderId(uid: string, now: number = Date.now()): string {
  const full = `PACIFIC-${uid}-${now}`;
  // PesaPal merchant reference: keep it under 50 chars.
  return full.length <= 50 ? full : `PACIFIC-${uid.slice(0, 8)}-${now}`;
}