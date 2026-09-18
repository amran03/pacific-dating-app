/**
 * pesapal-ipn — endpoint ambayo PesaPal inaipiga YENYEWE (webhook).
 * ---------------------------------------------------------------------------
 * HAKUNA auth ya mtumiaji hapa (PesaPal haiwezi kuwa na JWT yako), kwa hiyo
 * deploy kwa:  supabase functions deploy pesapal-ipn --no-verify-jwt
 *
 * Inapokea: ?OrderTrackingId=...&OrderMerchantReference=...&OrderNotificationType=...
 *   (GET ndiyo default; POST/JSON pia inakubaliwa)
 *
 * Inathibitisha status kwa GetTransactionStatus kisha inasasisha "transactions"
 * hadi COMPLETED/FAILED (service_role client -> inapita RLS). Kama COMPLETED,
 * coins zinaongezwa kwenye profile ya mtumiaji husika (idempotent).
 *
 * Inarudisha 200 + JSON ambayo PesaPal inatarajia kwa IPN ya GET.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  corsHeaders,
  jsonResponse,
  serviceRoleKey,
  supabaseUrl,
} from "../_shared/pesapal.ts";
import {
  resolveOrderTrackingId,
  syncOrderStatus,
} from "../_shared/order_status.ts";

interface IpnPayload {
  OrderTrackingId?: string;
  orderTrackingId?: string;
  OrderMerchantReference?: string;
  orderMerchantReference?: string;
  OrderNotificationType?: string;
  orderNotificationType?: string;
}

function firstNonEmpty(...values: (string | null | undefined)[]): string {
  for (const value of values) {
    const trimmed = (value ?? "").trim();
    if (trimmed.length > 0) return trimmed;
  }
  return "";
}

async function readIpnPayload(req: Request): Promise<IpnPayload> {
  const params = new URL(req.url).searchParams;
  const payload: IpnPayload = {
    OrderTrackingId: params.get("OrderTrackingId") ??
      params.get("orderTrackingId") ?? undefined,
    OrderMerchantReference: params.get("OrderMerchantReference") ??
      params.get("orderMerchantReference") ?? undefined,
    OrderNotificationType: params.get("OrderNotificationType") ??
      params.get("orderNotificationType") ?? undefined,
  };

  if (req.method !== "POST") return payload;

  const contentType = req.headers.get("content-type") ?? "";
  try {
    if (contentType.includes("application/json")) {
      const body = (await req.json()) as IpnPayload;
      payload.OrderTrackingId = firstNonEmpty(
        payload.OrderTrackingId,
        body.OrderTrackingId,
        body.orderTrackingId,
      );
      payload.OrderMerchantReference = firstNonEmpty(
        payload.OrderMerchantReference,
        body.OrderMerchantReference,
        body.orderMerchantReference,
      );
      payload.OrderNotificationType = firstNonEmpty(
        payload.OrderNotificationType,
        body.OrderNotificationType,
        body.orderNotificationType,
      );
    } else {
      const form = await req.formData();
      const get = (key: string) => {
        const value = form.get(key);
        return typeof value === "string" ? value : undefined;
      };
      payload.OrderTrackingId = firstNonEmpty(
        payload.OrderTrackingId,
        get("OrderTrackingId"),
        get("orderTrackingId"),
      );
      payload.OrderMerchantReference = firstNonEmpty(
        payload.OrderMerchantReference,
        get("OrderMerchantReference"),
        get("orderMerchantReference"),
      );
      payload.OrderNotificationType = firstNonEmpty(
        payload.OrderNotificationType,
        get("OrderNotificationType"),
        get("orderNotificationType"),
      );
    }
  } catch (error) {
    console.warn("pesapal-ipn: body parse failed:", error);
  }

  return payload;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await readIpnPayload(req);
    const notificationType = firstNonEmpty(
      payload.OrderNotificationType,
      "IPNCHANGE",
    );
    const merchantReference = firstNonEmpty(payload.OrderMerchantReference);
    let orderTrackingId = firstNonEmpty(payload.OrderTrackingId);

    const admin = createClient(supabaseUrl(), serviceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Kama PesaPal imetuma merchant reference pekee, tafuta tracking id yetu.
    if (!orderTrackingId && merchantReference) {
      orderTrackingId =
        (await resolveOrderTrackingId(admin, merchantReference)) ?? "";
    }

    if (!orderTrackingId) {
      return jsonResponse({
        orderNotificationType: notificationType,
        orderTrackingId: "",
        orderMerchantReference: merchantReference,
        status: 400,
        message:
          "OrderTrackingId/OrderMerchantReference haipo kwenye IPN request.",
      });
    }

    // Thibitisha kwa PesaPal + sasisha transactions (+ coins kama COMPLETED).
    const result = await syncOrderStatus(admin, orderTrackingId);
    console.log("pesapal-ipn processed:", JSON.stringify(result));

    return jsonResponse({
      orderNotificationType: notificationType,
      orderTrackingId,
      orderMerchantReference: result.orderId ?? merchantReference,
      status: 200,
      paymentStatus: result.status,
      credited: result.credited,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("pesapal-ipn error:", message);

    // 500 -> PesaPal itajaribu IPN tena baadaye (transient error).
    return jsonResponse({ status: 500, error: message }, 500);
  }
});