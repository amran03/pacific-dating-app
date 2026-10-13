/**
 * create-pesapal-order — called by Flutter (lib/services/pesapal_service.dart)
 * via supabase.functions.invoke('create-pesapal-order', body: {...}).
 * ---------------------------------------------------------------------------
 * 1. Verifies the user's JWT (auth required — deploy WITHOUT --no-verify-jwt).
 * 2. Calculates the amount SERVER SIDE (1 coin = 25 TZS) — the client's
 *    amount is never trusted.
 * 3. Creates the order with PesaPal (currency: TZS).
 * 4. Stores a PENDING record in "transactions" using service_role.
 *
 * Returns: { redirectUrl, orderId, orderTrackingId, amount, coins, currency }
 *
 * IMPORTANT: consumer_secret lives only in Supabase secrets.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildOrderId,
  corsHeaders,
  getToken,
  jsonResponse,
  pesapalCredentials,
  pesapalIpnId,
  serviceRoleKey,
  submitOrder,
  supabaseUrl,
} from "../_shared/pesapal.ts";

/** 1 Coin = 25 TZS — MUST match kCoinRateTzs in pesapal_service.dart */
const COIN_RATE_TZS = 25;
const MIN_COINS = 10;
const MAX_COINS = 200000;

interface CreateOrderBody {
  amount?: number | string;
  coins?: number | string;
  description?: string;
  email?: string;
  phone?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed. Use POST." }, 405);
  }

  try {
    // ---------- 1) Verify the user's JWT ----------
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse(
        { error: "Missing Authorization header. Please sign in first." },
        401,
      );
    }

    const url = supabaseUrl();
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) {
      return jsonResponse({ error: "Empty bearer token." }, 401);
    }

    // The anon key is only for the gateway; the user's JWT is verified by GoTrue.
    const anonKey = (Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      serviceRoleKey()).trim();

    const authClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await authClient.auth
      .getUser(jwt);
    if (userError || !userData?.user) {
      return jsonResponse(
        {
          error: "Invalid or expired session. Sign in again.",
          details: userError?.message,
        },
        401,
      );
    }
    const user = userData.user;

    // Service-role client: bypasses RLS for writing to "transactions".
    const admin = createClient(url, serviceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ---------- 2) Read and validate the body ----------
    const body = (await req.json().catch(() => ({}))) as CreateOrderBody;
    const requestedCoins = Number(body.coins ?? 0);
    const requestedAmount = Number(body.amount ?? 0);

    let coins = 0;
    if (Number.isFinite(requestedCoins) && requestedCoins > 0) {
      coins = Math.floor(requestedCoins);
    } else if (Number.isFinite(requestedAmount) && requestedAmount > 0) {
      coins = Math.floor(requestedAmount / COIN_RATE_TZS);
    }

    if (coins < MIN_COINS || coins > MAX_COINS) {
      return jsonResponse(
        { error: `Coins must be between ${MIN_COINS} and ${MAX_COINS}.` },
        400,
      );
    }

    // Kiasi KINAHESABIWA hapa (server side).
    const amount = coins * COIN_RATE_TZS;

    // ---------- 3) Billing details (email + phone are REQUIRED by PesaPal) ----------
    const profile = await admin
      .from("users")
      .select("phone_number, auth_email, name")
      .eq("uid", user.id)
      .maybeSingle();
    const profileRow = (profile.data ?? {}) as Record<string, unknown>;

    const email = cleanText(body.email) ??
      cleanText(profileRow.auth_email) ??
      cleanText(user.email) ?? "";
    const phone = normalizePhone(
      cleanText(body.phone) ?? cleanText(profileRow.phone_number) ?? "",
    );
    const description = cleanText(body.description) ?? `${coins} Pacific Coins`;

    if (!email.includes("@")) {
      return jsonResponse(
        { error: "A valid email address is required for PesaPal payments." },
        400,
      );
    }
    if (!phone) {
      return jsonResponse(
        { error: "A phone number is required for PesaPal payments." },
        400,
      );
    }

    const { firstName, lastName } = splitName(cleanText(profileRow.name) ?? "");
    const orderId = buildOrderId(user.id);
    const callbackUrl = `${url}/functions/v1/pesapal-return?orderId=${
      encodeURIComponent(orderId)
    }`;

    // ---------- 4) Create the order with PesaPal ----------
    const { consumerKey, consumerSecret } = pesapalCredentials();
    const token = await getToken(consumerKey, consumerSecret);

    const pesapalOrder = await submitOrder(token, {
      id: orderId,
      currency: "TZS",
      amount,
      description,
      callback_url: callbackUrl,
      notification_id: pesapalIpnId(),
      billing_address: {
        email_address: email,
        phone_number: phone,
        country_code: "TZ",
        first_name: firstName,
        last_name: lastName,
      },
    });

    if (!pesapalOrder.redirect_url || !pesapalOrder.order_tracking_id) {
      throw new Error(
        `PesaPal did not return redirect_url/order_tracking_id: ${
          JSON.stringify(pesapalOrder)
        }`,
      );
    }

    // ---------- 5) Store the PENDING record (service_role -> bypasses RLS) ----------
    const { error: insertError } = await admin.from("transactions").insert({
      id: orderId,
      uid: user.id,
      amount,
      coins,
      currency: "TZS",
      description,
      status: "PENDING",
      order_tracking_id: pesapalOrder.order_tracking_id,
      merchant_reference: pesapalOrder.merchant_reference ?? orderId,
      pesapal_status: pesapalOrder,
    });

    if (insertError) {
      throw new Error(
        `Failed to store the transaction: ${insertError.message}`,
      );
    }

    // ---------- 6) Return to Flutter ----------
    return jsonResponse({
      redirectUrl: pesapalOrder.redirect_url,
      orderId,
      orderTrackingId: pesapalOrder.order_tracking_id,
      amount,
      coins,
      currency: "TZS",
      description,
      merchantReference: pesapalOrder.merchant_reference ?? orderId,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("create-pesapal-order error:", message);
    return jsonResponse({ error: message }, 500);
  }
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function cleanText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** PesaPal expects the phone number without the country code (e.g. 0755123456). */
function normalizePhone(raw: string): string {
  const digits = raw.replace(/[^\d]/g, "");
  if (!digits) return "";
  if (digits.startsWith("255")) return `0${digits.slice(3)}`;
  if (digits.startsWith("0")) return digits;
  return `0${digits}`;
}

function splitName(fullName: string): { firstName: string; lastName: string } {
  const parts = fullName.split(/\s+/).filter((part) => part.length > 0);
  if (parts.length === 0) return { firstName: "Pacific", lastName: "Customer" };
  if (parts.length === 1) return { firstName: parts[0], lastName: "Customer" };
  return { firstName: parts[0], lastName: parts.slice(1).join(" ") };
}