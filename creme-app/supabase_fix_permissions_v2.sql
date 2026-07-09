-- ═══════════════════════════════════════════════════════
--  Fix: send-push fails with "permission denied for table
--  push_subscriptions" even though it uses the service role key.
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  Same root cause as supabase_fix_permissions.sql, one level
--  deeper: every table created via the SQL Editor this session
--  turns out to need EXPLICIT grants for every role that touches
--  it, including service_role — Postgres's BYPASSRLS attribute
--  (which is how service_role skips RLS policies) does NOT also
--  imply table-level GRANTs. Those are two separate permission
--  layers and both were missing.

grant select, insert, update, delete on push_subscriptions to service_role;
grant select, insert, update, delete on activity_feed      to service_role;
grant select, insert, update, delete on challenges          to service_role;
grant select, insert, update, delete on challenge_results   to service_role;
