/**
 * create-pesapal-order — Flutter (lib/services/pesapal_service.dart) inaita hii
 * kupitia supabase.functions.invoke('create-pesapal-order', body: {...}).
 * ---------------------------------------------------------------------------
 * 1. Inathibitisha JWT ya mtumiaji (auth required — deploy bila --no-verify-jwt).
 * 2. Inahesabu kiasi kwa SERVER SIDE (1 coin = 100 TZS) — hatutumii amount ya client.
 * 3. Inaunda order kwa PesaPal (currency: TZS).
 * 4. Inahifadhi rekodi ya PENDING kwenye "transactions" kwa service_role.
 *
 * Inarudisha: { redirectUrl, orderId, orderTrackingId, amount, coins, currency }
 *
 * MUHIMU: consumer_secret ipo kwenye Supabase secrets pekee.
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

/** 1 Coin = 25 TZS — LAZIMA ilingane na kCoinRateTzs kwenye pesapal_service.dart */
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
    // ---------- 1) Thibitisha JWT ya mtumiaji ----------
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonResponse(
        { error: "Missing Authorization header. Sign in kwanza." },
        401,
      );
    }

    const url = supabaseUrl();
    const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!jwt) {
      return jsonResponse({ error: "Empty bearer token." }, 401);
    }

    // Anon key ni ya gateway tu; JWT ya mtumiaji inathibitishwa na GoTrue.
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

    // Service-role client: inapita RLS kwa maandishi ya "transactions".
    const admin = createClient(url, serviceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ---------- 2) Soma na thibitisha body ----------
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
        { error: `Coins lazima ziwe kati ya ${MIN_COINS} na ${MAX_COINS}.` },
        400,
      );
    }

    // Kiasi KINAHESABIWA hapa (server side).
    const amount = coins * COIN_RATE_TZS;

    // ---------- 3) Taarifa za bili (email + phone ni LAZIMA kwa PesaPal) ----------
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
        { error: "Barua pepe (email) ni lazima kwa malipo ya PesaPal." },
        400,
      );
    }
    if (!phone) {
      return jsonResponse(
        { error: "Namba ya simu ni lazima kwa malipo ya PesaPal." },
        400,
      );
    }

    const { firstName, lastName } = splitName(cleanText(profileRow.name) ?? "");
    const orderId = buildOrderId(user.id);
    const callbackUrl = `${url}/functions/v1/pesapal-return?orderId=${
      encodeURIComponent(orderId)
    }`;

    // ---------- 4) Unda order kwa PesaPal ----------
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
        `PesaPal haikurudisha redirect_url/order_tracking_id: ${
          JSON.stringify(pesapalOrder)
        }`,
      );
    }

    // ---------- 5) Hifadhi rekodi ya PENDING (service_role -> inapita RLS) ----------
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
        `Imeshindwa kuhifadhi transaction: ${insertError.message}`,
      );
    }

    // ---------- 6) Rudisha kwa Flutter ----------
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

/** PesaPal inataka namba ya simu bila country code (mf. 0755123456). */
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