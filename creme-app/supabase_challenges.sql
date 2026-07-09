-- ═══════════════════════════════════════════════════════
--  Challenges, contestant editing & media fixes
--  Run once in the Supabase SQL Editor (safe to re-run).
--  Requires is_admin() from supabase_admin_contestants.sql.
-- ═══════════════════════════════════════════════════════

-- ── 1. Contestant editing + homepage featuring ─────────────
alter table contestants add column if not exists is_featured boolean default false;

drop policy if exists "Admins update contestants" on contestants;
create policy "Admins update contestants" on contestants
    for update to authenticated
    using (is_admin()) with check (is_admin());

-- ── 2. Fix Delete Picture (contestant diary media) ─────────
--  Deletes were silently blocked because no DELETE policy
--  existed on contestant_media. Give admins full control.
drop policy if exists "Admins manage contestant media" on contestant_media;
create policy "Admins manage contestant media" on contestant_media
    for all to authenticated
    using (is_admin()) with check (is_admin());

-- ── 3. Challenges / tasks ───────────────────────────────────
create table if not exists challenges (
    id            uuid primary key default gen_random_uuid(),
    title         text not null,
    description   text,
    starts_at     timestamptz,
    ends_at       timestamptz,
    marks         numeric,
    status        text not null default 'active' check (status in ('active','closed')),
    result_remark text,
    created_at    timestamptz default now()
);
alter table challenges enable row level security;
drop policy if exists "Public read challenges" on challenges;
create policy "Public read challenges" on challenges
    for select using (true);
drop policy if exists "Admins manage challenges" on challenges;
create policy "Admins manage challenges" on challenges
    for all to authenticated
    using (is_admin()) with check (is_admin());

-- ── 4. Challenge results / leaderboard ──────────────────────
create table if not exists challenge_results (
    id           uuid primary key default gen_random_uuid(),
    challenge_id uuid not null references challenges(id) on delete cascade,
    position     int not null,
    name         text not null,
    points       numeric,
    created_at   timestamptz default now()
);
alter table challenge_results enable row level security;
drop policy if exists "Public read challenge results" on challenge_results;
create policy "Public read challenge results" on challenge_results
    for select using (true);
drop policy if exists "Admins manage challenge results" on challenge_results;
create policy "Admins manage challenge results" on challenge_results
    for all to authenticated
    using (is_admin()) with check (is_admin());
