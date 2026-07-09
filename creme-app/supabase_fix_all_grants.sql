-- ═══════════════════════════════════════════════════════
--  Systemic fix: table GRANTs across the whole schema
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  "permission denied for table X" (SQLSTATE 42501) is a
--  different failure than an RLS policy rejection — it fires
--  BEFORE row-level security is evaluated at all. A table needs
--  BOTH a GRANT (can this role touch the table at all?) and a
--  passing RLS policy (which rows?) for any operation to work.
--
--  This project's tables never got the base GRANT that the
--  dashboard's Table Editor normally adds automatically — only
--  tables/columns created that way get it for free. We've now
--  hit this exact bug five separate times on five different
--  tables (activity_feed, challenges, challenge_results,
--  push_subscriptions, and now contestants' DELETE specifically,
--  since no feature ever exercised it before the admin-delete
--  button was added).
--
--  Fix: grant broadly across the whole schema and let RLS do
--  100% of the real access control, which is the standard
--  Supabase-recommended pattern — granting the table layer never
--  bypasses a single RLS policy already in place; it only stops
--  a missing GRANT from being an invisible extra lock RLS can't
--  see past. Every table here already has RLS enabled.
--
--  Also sets default privileges so every table created from now
--  on inherits this automatically — this bug class should not
--  be able to happen again.

grant select, insert, update, delete on all tables in schema public to authenticated;
grant select                        on all tables in schema public to anon;
grant select, insert, update, delete on all tables in schema public to service_role;

grant usage, select on all sequences in schema public to authenticated, service_role;

alter default privileges in schema public
    grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
    grant select on tables to anon;
alter default privileges in schema public
    grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public
    grant usage, select on sequences to authenticated, service_role;

-- Safety check: this grant only matters where RLS is OFF, since RLS
-- policies still gate every row regardless of the table grant. Any
-- row here means that table is now readable/writable by anyone
-- signed in, gated by nothing — check the list is empty (or expected).
select schemaname, tablename
from pg_tables
where schemaname = 'public'
  and rowsecurity = false;

