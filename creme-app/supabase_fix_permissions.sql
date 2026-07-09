-- ═══════════════════════════════════════════════════════
--  Fix missing table permissions from this session's new
--  tables, plus a missing update policy on system_settings.
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  Postgres requires TWO separate layers for a role to touch
--  a table: an RLS policy (controls which ROWS) and a GRANT
--  (controls whether the table is reachable AT ALL). The SQL
--  Editor doesn't auto-grant new tables to anon/authenticated
--  the way the dashboard's Table Editor does — so activity_feed,
--  challenges, and challenge_results all had correct RLS
--  policies but were unreachable regardless. This is why the
--  public Challenges/Tasks tab has been blank since it shipped,
--  and why the live feed showed nothing.

grant select on activity_feed to anon, authenticated;
grant delete on activity_feed to authenticated;

grant select on challenges to anon, authenticated;
grant insert, update, delete on challenges to authenticated;

grant select on challenge_results to anon, authenticated;
grant insert, update, delete on challenge_results to authenticated;

-- ── system_settings never had an UPDATE policy at all, only
--    the original "public read". Every Master App Controls
--    toggle (Lineup Reveal, Nominations, Voting, Ticket Sales,
--    Judges/Team reveal, Volunteer signups) has likely been
--    silently failing to save ever since that panel shipped. ──
grant update on system_settings to authenticated;
drop policy if exists "Admins update system_settings" on system_settings;
create policy "Admins update system_settings" on system_settings
    for update to authenticated
    using (is_admin())
    with check (is_admin());
