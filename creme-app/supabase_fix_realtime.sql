-- ═══════════════════════════════════════════════════════
--  Fix: live feed doesn't update instantly, only on reload
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  The app already listens for live changes on activity_feed and
--  re-renders the feed the instant a row appears — no page reload
--  needed. But Postgres only broadcasts changes for tables that have
--  been explicitly added to the "supabase_realtime" publication, and
--  the SQL Editor doesn't do that automatically the way the
--  dashboard's Table Editor does when you flip its Realtime toggle.
--  activity_feed was never added, so the listener was correctly
--  wired up but never actually received anything.

do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'activity_feed'
    ) then
        alter publication supabase_realtime add table activity_feed;
    end if;
end $$;
