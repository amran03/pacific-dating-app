// Edge Function: send-push — fans out an FCM DATA message to every
// fcm_token stored for the target user. Invoke with the service_role
// key (reads other users' tokens). Secrets: FCM_PROJECT_ID,
// FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function fcmAccessToken(): Promise<string> {
  const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
  let privateKey = Deno.env.get("FCM_PRIVATE_KEY") ?? "";
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error("FCM secrets missing (PROJECT_ID/CLIENT_EMAIL/KEY)");
  }
  privateKey = privateKey.replace(/\\n/g, "\n");
  const pem = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    raw.buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claim = b64url(
    new TextEncoder().encode(JSON.stringify({
      iss: clientEmail,
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })),
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const jwt = `${header}.${claim}.${b64url(new Uint8Array(sig))}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer" +
      `&assertion=${jwt}`,
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error("FCM token failed: " + JSON.stringify(json));
  }
  // Lazima turudi tokeni hii — bila hapa accessToken = undefined na
  // kila send itaishia 401 (Bearer undefined).
  return json.access_token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }
  try {
    const { createClient } = await import("jsr:@supabase/supabase-js@2");
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
    if (!url || !serviceKey) throw new Error("Supabase env missing");

    const body = await req.json();
    console.log("send-push called:", JSON.stringify(body));
    const toUid = (body.to_uid ?? "").toString();
    if (!toUid) throw new Error("to_uid required");
    const type = (body.type ?? "message").toString();
    const title = (body.title ?? "Pacific").toString();
    const msgBody = (body.body ?? "").toString();
    const fromUid = (body.from_uid ?? "").toString();
    const fromName = (body.from_name ?? "").toString();

    const db = createClient(url, serviceKey);
    const { data: rows } = await db
      .from("users")
      .select("fcm_token")
      .eq("uid", toUid)
      .not("fcm_token", "is", null);
    const tokens = (rows ?? [])
      .map((r: { fcm_token?: string | null }) => r.fcm_token ?? "")
      .filter((t: string) => t.length > 10);
    if (tokens.length === 0) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await fcmAccessToken();
    const data: Record<string, string> = {
      type,
      title,
      body: msgBody,
      from_uid: fromUid,
      from_name: fromName,
    };
    if (type === "call") {
      data.call_id = (body.call_id ?? "").toString();
      data.is_video = body.is_video == true ? "true" : "false";
    }

    // Android HIGH priority so onBackgroundMessage fires even when the
    // app is killed. Calls also carry a notification payload so the
    // system wakes the device even if data delivery is delayed.
    let sent = 0;
    for (const token of tokens) {
      const message: Record<string, unknown> = {
        token,
        data,
        android: {
          priority: "HIGH",
          ttl: type === "call" ? "60s" : "86400s",
        },
      };
      if (type === "call") {
       message.notification = { title, body: msgBody };
      }
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ message }),
        },
      );
      if (res.ok) {
        sent++;
      } else {
        console.error("FCM send failed", res.status, await res.text());
      }
    }
    // Rudisha Response ya mafanikio — handler isiporudi chochote,
    // Deno hutoa error hata kama send zote zimefanikiwa.
    return new Response(JSON.stringify({ ok: true, sent }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : "failed" }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
