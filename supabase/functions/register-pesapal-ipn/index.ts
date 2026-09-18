/**
 * register-pesapal-ipn — inapigwa KWA MKONO MARA MOJA TU.
 * ---------------------------------------------------------------------------
 * Inasajili IPN URL yetu kwa PesaPal na kurudisha { ipn_id }. ipn_id hiyo
 * inawekwa kama secret:  supabase secrets set PESAPAL_IPN_ID=<ipn_id>
 *
 * ULINZI: function hii inahitaji ama
 *   - header  x-admin-secret: <PESAPAL_ADMIN_SECRET>   (pendekezo)
 *   - au     Authorization: Bearer <SERVICE_ROLE_KEY>
 * hivyo mtu asiyeruhusiwa hawezi kubadilisha IPN URL ya akaunti yako.
 *
 * Deploy:  supabase functions deploy register-pesapal-ipn --no-verify-jwt
 * Ita:     curl -X POST ".../functions/v1/register-pesapal-ipn" \
 *            -H "x-admin-secret: $PESAPAL_ADMIN_SECRET" \
 *            -H "Content-Type: application/json" \
 *            -d '{"ipnUrl":"https://<ref>.supabase.co/functions/v1/pesapal-ipn"}'
 */
import {
  corsHeaders,
  getIpnList,
  getToken,
  jsonResponse,
  pesapalCredentials,
  registerIPN,
  supabaseUrl,
} from "../_shared/pesapal.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ---------- 1) Ulinzi (function inapigwa kwa mkono, sio kila siku) ----------
    const adminSecret = (Deno.env.get("PESAPAL_ADMIN_SECRET") ?? "").trim();
    const providedSecret = (req.headers.get("x-admin-secret") ?? "").trim();
    const authHeader = (req.headers.get("Authorization") ?? "").trim();
    const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();

    const isServiceRole = serviceKey.length > 20 &&
      authHeader === `Bearer ${serviceKey}`;
    const isAdmin = adminSecret.length > 0 && providedSecret === adminSecret;

    if (!isServiceRole && !isAdmin) {
      return jsonResponse(
        {
          error: "Unauthorized",
          hint:
            "Weka secret PESAPAL_ADMIN_SECRET kisha tuma header x-admin-secret, " +
            "au tuma Authorization: Bearer <SERVICE_ROLE_KEY>.",
        },
        401,
      );
    }

    // ---------- 2) Chagua IPN URL ----------
    const body = await req.json().catch(() => ({})) as {
      ipnUrl?: string;
      url?: string;
      notificationType?: string;
    };
    const ipnUrl = (body.ipnUrl ?? body.url ?? "").trim() ||
      `${supabaseUrl()}/functions/v1/pesapal-ipn`;
    const notificationType = body.notificationType === "POST" ? "POST" : "GET";

    if (!ipnUrl.startsWith("https://")) {
      return jsonResponse(
        { error: "IPN URL lazima iwe https:// (PesaPal hairuhusu http)." },
        400,
      );
    }

    // ---------- 3) Wasiliana na PesaPal ----------
    const { consumerKey, consumerSecret } = pesapalCredentials();
    const token = await getToken(consumerKey, consumerSecret);

    // Kama IPN hii ilikwisha sajiliwa (URL ile ile), tumia ipn_id ile ile.
    // PesaPal haina endpoint ya "update" — kusajili tena kunatengeneza duplicate.
    const existing = await getIpnList(token).catch(() => []);
    const already = existing.find((ipn) =>
      (ipn.url ?? ipn.ipn_url ?? "").trim() === ipnUrl
    );

    if (already?.ipn_id) {
      return jsonResponse({
        ok: true,
        reused: true,
        ipn_id: already.ipn_id,
        ipnUrl,
        notificationType: already.ipn_notification_type ?? notificationType,
        next: `supabase secrets set PESAPAL_IPN_ID=${already.ipn_id}`,
      });
    }

    const registration = await registerIPN(token, ipnUrl, notificationType);

    return jsonResponse({
      ok: true,
      ipn_id: registration.ipn_id,
      ipnUrl,
      notificationType,
      created_date: registration.created_date,
      next: `supabase secrets set PESAPAL_IPN_ID=${registration.ipn_id}`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("register-pesapal-ipn error:", message);
    return jsonResponse({ error: message }, 500);
  }
});