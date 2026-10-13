/**
 * pesapal-return — callback_url: a small HTML page shown in the user's
 * webview after paying.
 * ---------------------------------------------------------------------------
 * There is NO user auth (PesaPal/the webview opens it), so deploy with:
 *   supabase functions deploy pesapal-return --no-verify-jwt
 *
 * Its job:
 *  1. Verify the status with PesaPal (fallback if the IPN is delayed) and
 *     update "transactions" (+ coins when COMPLETED).
 *  2. Return a nice HTML page telling the user to go back to the app.
 *
 * PaymentWebViewScreen detects this URL (it contains "pesapal-return") and
 * then waits for the COMPLETED/FAILED status from the transactions table.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { htmlResponse, serviceRoleKey, supabaseUrl } from "../_shared/pesapal.ts";
import {
  resolveOrderTrackingId,
  syncOrderStatus,
} from "../_shared/order_status.ts";

interface PageState {
  headline: string;
  detail: string;
  tone: "success" | "pending" | "error";
  orderId: string;
}

Deno.serve(async (req) => {
  const params = new URL(req.url).searchParams;
  const orderTrackingId = (params.get("OrderTrackingId") ??
    params.get("orderTrackingId") ?? "").trim();
  const orderId = (params.get("orderId") ??
    params.get("OrderMerchantReference") ?? "").trim();

  const state: PageState = {
    headline: "Payment received",
    detail:
      "Your payment is being confirmed. You can go back to the Pacific app — your coins will appear automatically.",
    tone: "pending",
    orderId,
  };

  try {
    if (orderTrackingId || orderId) {
      const admin = createClient(supabaseUrl(), serviceRoleKey(), {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      let trackingId = orderTrackingId;
      if (!trackingId && orderId) {
        trackingId = (await resolveOrderTrackingId(admin, orderId)) ?? "";
      }

      if (trackingId) {
        const result = await syncOrderStatus(admin, trackingId);

        if (result.status === "COMPLETED") {
          state.headline = "Payment successful";
          state.detail = result.credited
            ? "Your coins have been added to your Pacific wallet. Enjoy!"
            : "Your payment was already confirmed — your coins are in your wallet.";
          state.tone = "success";
        } else if (result.status === "FAILED") {
          state.headline = "Payment failed";
          state.detail =
            "The payment was not completed. No coins were added. Please go back to the app and try again.";
          state.tone = "error";
        } else {
          state.headline = "Payment pending";
          state.detail =
            "We are still confirming your payment with PesaPal. Coins will be added as soon as it is confirmed.";
          state.tone = "pending";
        }
      }
    }
  } catch (error) {
    console.error(
      "pesapal-return sync error:",
      error instanceof Error ? error.message : String(error),
    );
  }

  return htmlResponse(renderPage(state));
});

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderPage(state: PageState): string {
  const tones: Record<PageState["tone"], { color: string; icon: string }> = {
    success: { color: "#16A34A", icon: "&#10003;" },
    pending: { color: "#F59E0B", icon: "&#8987;" },
    error: { color: "#DC2626", icon: "&#10007;" },
  };
  const tone = tones[state.tone];
  const orderLine = state.orderId
    ? `<p class="order">Order: <strong>${escapeHtml(state.orderId)}</strong></p>`
    : "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Pacific Dating App - Payment</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: #F8F9FA;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #1F2937;
    }
    .card {
      width: 100%;
      max-width: 420px;
      background: #FFFFFF;
      border-radius: 24px;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 12px 32px rgba(0, 0, 0, 0.08);
    }
    .badge {
      width: 72px;
      height: 72px;
      margin: 0 auto 18px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 34px;
      color: #FFFFFF;
      background: ${tone.color};
    }
    h1 { font-size: 20px; margin: 0 0 10px; }
    p { font-size: 14px; line-height: 1.5; color: #4B5563; margin: 0 0 14px; }
    .order { font-size: 12px; color: #9CA3AF; word-break: break-all; }
    .note {
      margin-top: 18px;
      padding: 12px 14px;
      background: #FFF1F4;
      border-radius: 14px;
      font-size: 13px;
      color: #BE123C;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">${tone.icon}</div>
    <h1>${escapeHtml(state.headline)}</h1>
    <p>${escapeHtml(state.detail)}</p>
    ${orderLine}
    <div class="note">You can close this page and go back to the Pacific app now.</div>
  </div>
</body>
</html>`;
}