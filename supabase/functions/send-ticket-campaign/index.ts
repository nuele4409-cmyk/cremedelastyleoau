// send-ticket-campaign — emails every paid ticket holder a PDF ticket
// (QR code + tier + event date/time/venue) as a reminder before the event.
//
// Admin-only: verifies the caller's own session actually has the admin
// role before doing anything — this isn't just a UI-level restriction,
// the function checks it independently.
//
// Secrets required (Edge Functions → Secrets):
//   RESEND_API_KEY   — from resend.com, after verifying a sending domain
//   CAMPAIGN_FROM    — e.g. "Crème De La Style <tickets@cremedelastyleoau.com>"
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, rgb, StandardFonts } from "npm:pdf-lib@1.17.1";
import QRCode from "npm:qrcode@1.5.3";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

async function buildTicketPdf(opts: {
  holderName: string; tier: string; amount: number; entryToken: string;
  eventDateLabel: string; venue: string;
}): Promise<Uint8Array> {
  const qrPng = await QRCode.toBuffer(opts.entryToken, { type: "png", width: 260, margin: 1 });

  const pdf = await PDFDocument.create();
  const page = pdf.addPage([360, 620]);
  const font = await pdf.embedFont(StandardFonts.HelveticaBold);
  const fontReg = await pdf.embedFont(StandardFonts.Helvetica);
  const gold = rgb(0.83, 0.69, 0.22);
  const cream = rgb(0.98, 0.96, 0.89);
  const dark = rgb(0.02, 0, 0.02);

  page.drawRectangle({ x: 0, y: 0, width: 360, height: 620, color: dark });
  page.drawText("CRÈME DE LA STYLE", { x: 60, y: 570, size: 16, font, color: gold });
  page.drawText("OAU Official Hub", { x: 128, y: 550, size: 9, font: fontReg, color: cream });

  page.drawText(opts.tier.toUpperCase() + " TICKET", { x: 40, y: 500, size: 18, font, color: cream });
  page.drawText(opts.holderName, { x: 40, y: 475, size: 13, font: fontReg, color: cream });
  page.drawText("Amount: NGN " + opts.amount.toLocaleString(), { x: 40, y: 455, size: 10, font: fontReg, color: gold });

  const qrImg = await pdf.embedPng(qrPng);
  page.drawImage(qrImg, { x: 50, y: 220, width: 260, height: 260 });

  page.drawText("Entry Token:", { x: 40, y: 195, size: 9, font: fontReg, color: cream });
  page.drawText(opts.entryToken, { x: 40, y: 180, size: 8, font: fontReg, color: gold });

  page.drawLine({ start: { x: 40, y: 160 }, end: { x: 320, y: 160 }, thickness: 0.5, color: gold });

  page.drawText("📅 " + opts.eventDateLabel, { x: 40, y: 130, size: 11, font: fontReg, color: cream });
  page.drawText("📍 " + opts.venue, { x: 40, y: 108, size: 11, font: fontReg, color: cream });
  page.drawText("Present this QR code at the door for entry.", { x: 40, y: 75, size: 8, font: fontReg, color: cream });
  page.drawText("Seats are strictly limited — all sales are final.", { x: 40, y: 60, size: 8, font: fontReg, color: cream });

  return pdf.save();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const callerToken = authHeader.replace(/^Bearer\s+/i, "");
    if (!callerToken) return json({ ok: false, error: "Not authenticated" }, 401);

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Verify the caller is genuinely who their token says, then check the
    // admin role server-side — never trust a client-supplied "I'm an admin".
    const { data: callerUser, error: callerErr } = await sb.auth.getUser(callerToken);
    if (callerErr || !callerUser?.user) return json({ ok: false, error: "Not authenticated" }, 401);
    const { data: roleRow } = await sb.from("user_roles").select("role").eq("user_id", callerUser.user.id).maybeSingle();
    if (!roleRow || roleRow.role !== "admin") return json({ ok: false, error: "Admin access required" }, 403);

    const resendKey = Deno.env.get("RESEND_API_KEY");
    const fromAddr = Deno.env.get("CAMPAIGN_FROM");
    if (!resendKey || !fromAddr) return json({ ok: false, error: "Email campaign is not configured (missing RESEND_API_KEY or CAMPAIGN_FROM)" }, 500);

    const { data: settings } = await sb.from("system_settings").select("event_date, venue").eq("id", 1).single();
    const venue = settings?.venue || "Venue to be confirmed";
    const eventDate = settings?.event_date ? new Date(settings.event_date) : null;
    const eventDateLabel = eventDate
      ? eventDate.toLocaleString("en-GB", { weekday: "long", day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) + " (WAT)"
      : "Date to be confirmed";

    const { data: tickets, error: tErr } = await sb
      .from("tickets")
      .select("id, user_id, tier_name, amount, entry_token")
      .eq("payment_status", "paid");
    if (tErr) return json({ ok: false, error: tErr.message }, 500);
    if (!tickets?.length) return json({ ok: true, sent: 0, failed: 0, total: 0, note: "No paid tickets found" });

    let sent = 0, failed = 0;
    const failures: string[] = [];

    for (const t of tickets) {
      try {
        const { data: userRes } = await sb.auth.admin.getUserById(t.user_id);
        const email = userRes?.user?.email;
        if (!email) { failed++; failures.push(t.id + ": no email on account"); continue; }
        const holderName = (userRes?.user?.user_metadata?.full_name as string) || email.split("@")[0];

        const pdfBytes = await buildTicketPdf({
          holderName, tier: t.tier_name, amount: Number(t.amount),
          entryToken: t.entry_token || t.id, eventDateLabel, venue,
        });
        const pdfBase64 = btoa(String.fromCharCode(...pdfBytes));

        const emailRes = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            from: fromAddr,
            to: email,
            subject: `Your ${t.tier_name} Ticket — Crème De La Style, ${eventDateLabel}`,
            html: `
              <div style="font-family:Georgia,serif;background:#0a0005;color:#f4f1de;padding:32px;">
                <h2 style="color:#d4af37;margin:0 0 4px;">Crème De La Style</h2>
                <p style="color:#f4f1de;opacity:0.7;margin:0 0 24px;">OAU Official Hub</p>
                <p>Hi ${holderName},</p>
                <p>This is your reminder — your <strong>${t.tier_name}</strong> ticket is attached as a PDF, QR code included.</p>
                <p>📅 <strong>${eventDateLabel}</strong><br>📍 <strong>${venue}</strong></p>
                <p>Please present the QR code in the attached PDF at the door for entry. See you there!</p>
              </div>`,
            attachments: [{ filename: "creme-de-la-style-ticket.pdf", content: pdfBase64 }],
          }),
        });
        if (!emailRes.ok) { failed++; failures.push(t.id + ": " + await emailRes.text()); continue; }
        sent++;
      } catch (e) {
        failed++;
        failures.push(t.id + ": " + String(e instanceof Error ? e.message : e));
      }
    }

    return json({ ok: true, sent, failed, total: tickets.length, failures: failures.slice(0, 10) });
  } catch (e) {
    return json({ ok: false, error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
