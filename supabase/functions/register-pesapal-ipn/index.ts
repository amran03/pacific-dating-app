/**
 * register-pesapal-ipn — called MANUALLY, ONCE.
 * ---------------------------------------------------------------------------
 * It registers our IPN URL with PesaPal and returns { ipn_id }. That ipn_id
 * is then stored as a secret:  supabase secrets set PESAPAL_IPN_ID=<ipn_id>
 *
 * PROTECTION: this function requires either
 *   - header  x-admin-secret: <PESAPAL_ADMIN_SECRET>   (recommended)
 *   - or     Authorization: Bearer <SERVICE_ROLE_KEY>
 * so an unauthorized person cannot change your account's IPN URL.
 *
 * Deploy:  supabase functions deploy register-pesapal-ipn --no-verify-jwt
 * Call:    curl -X POST ".../functions/v1/register-pesapal-ipn" \
 *             -H "x-admin-secret: $PESAPAL_ADMIN_SECRET" \
 *             -H "Content-Type: application/json" \
 *             -d '{"ipnUrl":"https://<ref>.supabase.co/functions/v1/pesapal-ipn"}'
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
    // ---------- 1) Protection (this function is called manually, not daily) ----------
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
            "Set the PESAPAL_ADMIN_SECRET secret and send the x-admin-secret header, " +
            "or send Authorization: Bearer <SERVICE_ROLE_KEY>.",
        },
        401,
      );
    }

    // ---------- 2) Choose the IPN URL ----------
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
        { error: "The IPN URL must start with https:// (PesaPal does not allow http)." },
        400,
      );
    }

    // ---------- 3) Talk to PesaPal ----------
    const { consumerKey, consumerSecret } = pesapalCredentials();
    const token = await getToken(consumerKey, consumerSecret);

    // If this IPN was already registered (same URL), reuse the same ipn_id.
    // PesaPal has no "update" endpoint — re-registering creates a duplicate.
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