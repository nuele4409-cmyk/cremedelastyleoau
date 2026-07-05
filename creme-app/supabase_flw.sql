-- ═══════════════════════════════════════════════════════
--  Flutterwave integration — run once in the SQL Editor
-- ═══════════════════════════════════════════════════════

-- Server-verified payment flag for contestant applications
alter table contestants add column if not exists payment_verified boolean default false;

-- Safety net: make sure the nomination confirmation flag exists
-- (it was originally added via the dashboard, not supabase_setup.sql)
alter table nominations add column if not exists payment_confirmed boolean default false;
