-- ═══════════════════════════════════════════════════════
--  Fix "App Sign-ups" stat on the Analytics dashboard
--  Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════
--  get_user_count() was returning the wrong figure. Redefined
--  to count directly from Supabase's own auth.users table —
--  the authoritative record of every account ever created
--  (Google or email), rather than some other proxy table.

-- The live function has a different return type (e.g. int vs bigint),
-- and Postgres won't let CREATE OR REPLACE change that — drop it first.
drop function if exists get_user_count();

create function get_user_count()
returns bigint
language sql stable security definer
set search_path = public
as $$
    select count(*) from auth.users;
$$;

grant execute on function get_user_count() to authenticated, anon;
