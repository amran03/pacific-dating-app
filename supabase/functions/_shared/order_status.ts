/**
 * Shared status-sync logic — verifies the payment with PesaPal and then
 * updates the "transactions" table (and coins) using service_role.
 *
 * Used by:
 *   - pesapal-ipn     (webhook that PesaPal calls by itself)
 *   - pesapal-return  (callback fallback, if the IPN is delayed)
 *
 * IDEMPOTENT: coins are credited only once (pesapal_credit_coins).
 */
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  getToken,
  getTransactionStatus,
  mapStatusCodeToDbStatus,
  type PaymentDbStatus,
  pesapalCredentials,
  type PesapalTransactionStatus,
} from "./pesapal.ts";

export interface SyncResult {
  orderId: string | null;
  status: PaymentDbStatus | "UNKNOWN";
  credited: boolean;
  paymentMethod?: string;
  paymentStatusDescription?: string;
  message?: string;
}

/** Look up the stored OrderTrackingId for an order id (merchant reference). */
export async function resolveOrderTrackingId(
  admin: SupabaseClient,
  merchantReference: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from("transactions")
    .select("order_tracking_id")
    .eq("id", merchantReference)
    .maybeSingle();

  if (error) return null;
  return (data?.order_tracking_id as string | null) ?? null;
}

export async function syncOrderStatus(
  admin: SupabaseClient,
  orderTrackingId: string,
): Promise<SyncResult> {
  const { consumerKey, consumerSecret } = pesapalCredentials();
  const token = await getToken(consumerKey, consumerSecret);
  const pesapal: PesapalTransactionStatus = await getTransactionStatus(
    token,
    orderTrackingId,
  );

  const orderId = (pesapal.merchant_reference ?? "").trim() || null;
  const dbStatus = mapStatusCodeToDbStatus(
    pesapal.status_code,
    pesapal.payment_status_description,
  );

  const base = {
    orderId,
    credited: false,
    paymentMethod: pesapal.payment_method,
    paymentStatusDescription: pesapal.payment_status_description,
    message: pesapal.message ?? pesapal.description,
  };

  if (!orderId) {
    return { ...base, status: "UNKNOWN" };
  }

  const { data: tx, error: txError } = await admin
    .from("transactions")
    .select("id, uid, coins, status, credited")
    .eq("id", orderId)
    .maybeSingle();

  if (txError) {
    throw new Error(`Failed to read the transaction: ${txError.message}`);
  }
  if (!tx) {
    return { ...base, status: dbStatus };
  }

  if (dbStatus === "COMPLETED") {
    // Atomic + idempotent: coins are credited ONCE per order.
    const { data: credited, error: rpcError } = await admin.rpc(
      "pesapal_credit_coins",
      {
        p_order_id: orderId,
        p_coins: (tx.coins as number | null) ?? 0,
        p_status: pesapal,
      },
    );

    if (rpcError) {
      throw new Error(
        `Failed to credit coins (pesapal_credit_coins): ${rpcError.message}`,
      );
    }

    return { ...base, status: "COMPLETED", credited: credited === true };
  }

  const nowIso = new Date().toISOString();
  const auditFields = {
    order_tracking_id: orderTrackingId,
    payment_method: pesapal.payment_method ?? null,
    payment_status_description: pesapal.payment_status_description ?? null,
    pesapal_status: pesapal,
    updated_at: nowIso,
  };

  if (dbStatus === "FAILED") {
    const { error } = await admin
      .from("transactions")
      .update({ ...auditFields, status: "FAILED" })
      .eq("id", orderId)
      .eq("status", "PENDING"); // never change an order that is already COMPLETED

    if (error) throw new Error(`Failed to set FAILED: ${error.message}`);
    return { ...base, status: "FAILED" };
  }

  // Still PENDING: just store the latest details (the status stays unchanged).
  if (tx.status === "PENDING") {
    const { error } = await admin
      .from("transactions")
      .update(auditFields)
      .eq("id", orderId)
      .eq("status", "PENDING");

    if (error) throw new Error(`Failed to update the transaction: ${error.message}`);
  }

  return { ...base, status: "PENDING" };
}