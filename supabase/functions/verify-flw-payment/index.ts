// verify-flw-payment — server-side Flutterwave payment verification.
//
// The frontend calls this after the inline checkout callback with the
// transaction_id Flutterwave returned. We re-verify the transaction against
// Flutterwave's API using the SECRET key (stored only as an Edge Function
// secret, never in the repo) and only then mark the record paid.
//
// Secrets required (set via dashboard → Edge Functions → Secrets, or CLI):
//   FLW_SECRET_KEY  — your Flutterwave LIVE secret key (FLWSECK-...)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    const { transaction_id, tx_ref, kind } = await req.json();
    if (!transaction_id || !tx_ref || !["ticket", "nomination", "contestant"].includes(kind)) {
      return json({ ok: false, error: "Bad request" }, 400);
    }

    const flwKey = Deno.env.get("FLW_SECRET_KEY");
    if (!flwKey) return json({ ok: false, error: "Payment verification is not configured" }, 500);

    const vr = await fetch(
      `https://api.flutterwave.com/v3/transactions/${encodeURIComponent(transaction_id)}/verify`,
      { headers: { Authorization: `Bearer ${flwKey}` } },
    );
    const vj = await vr.json();
    const d = vj?.data;
    if (!d || d.status !== "successful" || d.currency !== "NGN" || d.tx_ref !== tx_ref) {
      return json({ ok: false, error: "Transaction not successful or reference mismatch" }, 400);
    }
    const paidAmount = Number(d.amount);

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    if (kind === "ticket") {
      const { data: t, error } = await sb
        .from("tickets")
        .select("id, amount, payment_status")
        .eq("payment_reference", tx_ref)
        .single();
      if (error || !t) return json({ ok: false, error: "Ticket not found" }, 404);
      if (paidAmount < Number(t.amount)) {
        return json({ ok: false, error: "Amount paid is below the ticket price" }, 400);
      }
      if (t.payment_status !== "paid") {
        const { error: uerr } = await sb.from("tickets").update({ payment_status: "paid" }).eq("id", t.id);
        if (uerr) return json({ ok: false, error: uerr.message }, 500);
      }
      return json({ ok: true });
    }

    if (kind === "nomination") {
      if (paidAmount < 100) return json({ ok: false, error: "Amount paid is below the nomination fee" }, 400);
      const { data: n, error } = await sb
        .from("nominations")
        .update({ payment_confirmed: true })
        .eq("payment_ref", tx_ref)
        .select("id");
      if (error) return json({ ok: false, error: error.message }, 500);
      if (!n?.length) return json({ ok: false, error: "Nomination not found" }, 404);
      return json({ ok: true });
    }

    // contestant
    if (paidAmount < 3000) return json({ ok: false, error: "Amount paid is below the registration fee" }, 400);
    const { data: c, error } = await sb
      .from("contestants")
      .update({ payment_verified: true })
      .eq("payment_ref", tx_ref)
      .select("id");
    if (error) return json({ ok: false, error: error.message }, 500);
    if (!c?.length) return json({ ok: false, error: "Application not found" }, 404);
    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
