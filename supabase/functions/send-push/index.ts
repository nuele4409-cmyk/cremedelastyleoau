// send-push — sends a Web Push notification to every subscribed device.
//
// Called automatically by a Postgres trigger the instant a new row lands
// in activity_feed (see supabase_push_notifications.sql), so every live
// feed update reaches subscribed phones' notification bars with no
// manual step.
//
// Secrets required (Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY   — same value embedded in creme-app/index.html
//   VAPID_PRIVATE_KEY  — never exposed to the client
//   VAPID_SUBJECT      — a mailto: contact address, e.g. mailto:you@example.com
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("POST only", { status: 405, headers: CORS });

  try {
    const { title, body, link_tab, image_url } = await req.json();

    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT")!,
      Deno.env.get("VAPID_PUBLIC_KEY")!,
      Deno.env.get("VAPID_PRIVATE_KEY")!,
    );

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: subs, error } = await sb.from("push_subscriptions").select("*");
    if (error) return new Response(JSON.stringify({ ok: false, error: error.message }), { status: 500, headers: CORS });

    const payload = JSON.stringify({
      title: title || "Crème De La Style",
      body: body || "",
      link_tab: link_tab || null,
      image_url: image_url || null,
    });

    let sent = 0, removed = 0;
    await Promise.all((subs || []).map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
          payload,
        );
        sent++;
      } catch (e) {
        const status = e && typeof e === "object" && "statusCode" in e ? (e as { statusCode: number }).statusCode : 0;
        if (status === 404 || status === 410) {
          await sb.from("push_subscriptions").delete().eq("id", s.id);
          removed++;
        }
      }
    }));

    return new Response(JSON.stringify({ ok: true, sent, removed, total: (subs || []).length }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e instanceof Error ? e.message : e) }), {
      status: 500,
      headers: CORS,
    });
  }
});
