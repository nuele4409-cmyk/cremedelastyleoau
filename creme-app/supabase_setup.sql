-- ══════════════════════════════════════════════════════
--  CRÈME DE LA STYLE — Supabase Database Setup
--  Paste this entire file into the Supabase SQL Editor
--  and click RUN. All tables will be created at once.
-- ══════════════════════════════════════════════════════


-- ── 1. SYSTEM SETTINGS ───────────────────────────────
--  Stores the event date (admin editable without redeploying)

create table if not exists system_settings (
    id           serial primary key,
    event_date   timestamptz not null default '2026-11-26T19:00:00+01:00',
    updated_at   timestamptz default now()
);

-- Insert the default event date row (only once)
insert into system_settings (event_date)
select '2026-11-26T19:00:00+01:00'
where not exists (select 1 from system_settings);

-- Allow anyone to read system settings
alter table system_settings enable row level security;
create policy "Public read system_settings"
    on system_settings for select using (true);


-- ── 2. TICKETS ────────────────────────────────────────
--  Stores purchased tickets with payment status & QR token

create table if not exists tickets (
    id                 uuid primary key default gen_random_uuid(),
    user_id            uuid references auth.users(id) on delete cascade,
    tier_name          text not null,
    amount             numeric(10,2) not null,
    payment_status     text not null default 'pending',  -- 'pending' | 'paid' | 'failed'
    payment_reference  text,
    entry_token        text unique,
    created_at         timestamptz default now()
);

alter table tickets enable row level security;

-- Users can only see their own tickets
create policy "Users read own tickets"
    on tickets for select using (auth.uid() = user_id);

-- Users can insert their own ticket records
create policy "Users insert own tickets"
    on tickets for insert with check (auth.uid() = user_id);


-- ── 3. CONTESTANTS ────────────────────────────────────
--  Contestant profiles; only approved ones are shown publicly

create table if not exists contestants (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid references auth.users(id) on delete cascade,
    full_name     text not null,
    email         text,
    phone         text,
    department    text,
    height        numeric,
    waist         numeric,
    hips          numeric,
    stat_unit     text default 'cm',       -- 'cm' or 'in'
    instagram     text,
    tiktok        text,
    headshot_url  text,
    fullbody_url  text,
    about_me      text,
    why_picked    text,
    is_approved   boolean not null default false,
    created_at    timestamptz default now()
);

alter table contestants enable row level security;

-- Public can only see approved contestants
create policy "Public read approved contestants"
    on contestants for select using (is_approved = true);

-- Authenticated users can insert their own profile
create policy "Users insert own contestant"
    on contestants for insert with check (auth.uid() = user_id);

-- Users can update their own profile
create policy "Users update own contestant"
    on contestants for update using (auth.uid() = user_id);


-- ── 4. NOTIFICATIONS ─────────────────────────────────
--  Admin-pushed broadcast messages shown to all users

create table if not exists notifications (
    id          uuid primary key default gen_random_uuid(),
    title       text not null,
    message     text not null,
    type        text not null default 'info',  -- 'info' | 'alert' | 'update'
    created_at  timestamptz default now()
);

alter table notifications enable row level security;

-- Anyone can read notifications
create policy "Public read notifications"
    on notifications for select using (true);

-- Insert sample notification so the UI is populated immediately
insert into notifications (title, message, type)
values (
    'Welcome to Crème De La Style!',
    'The most anticipated fashion event in OAU history is here. Stay tuned for updates on nominees, tickets, and the event date.',
    'info'
);


-- ── 5. NOMINATIONS ────────────────────────────────────
--  Nominations submitted by users (includes WhatsApp number)

create table if not exists nominations (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid references auth.users(id) on delete set null,
    nominee_name     text not null,
    category         text not null,
    social_handle    text,
    reason           text,
    whatsapp_number  text,
    created_at       timestamptz default now()
);

alter table nominations enable row level security;

-- Users can submit nominations
create policy "Users insert nominations"
    on nominations for insert with check (auth.uid() = user_id);

-- Users can view their own nominations
create policy "Users read own nominations"
    on nominations for select using (auth.uid() = user_id);


-- ── 5. REGISTRATIONS ─────────────────────────────────
--  Attendee / Volunteer registrations (non-contestant)

create table if not exists registrations (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid references auth.users(id) on delete set null,
    full_name    text not null,
    email        text not null,
    phone        text,
    department   text,
    type         text not null,   -- 'attendee' | 'volunteer'
    created_at   timestamptz default now()
);

alter table registrations enable row level security;

create policy "Users insert registrations"
    on registrations for insert with check (auth.uid() = user_id);

create policy "Users read own registrations"
    on registrations for select using (auth.uid() = user_id);


-- ══════════════════════════════════════════════════════
--  STORAGE BUCKETS
--  After running this SQL, go to:
--  Storage → New Bucket and create these two buckets:
--
--    Name: contestant-headshots   ✓ Public bucket
--    Name: contestant-fullbody    ✓ Public bucket
--
--  Then add this storage policy to each bucket:
--    Policy: Allow authenticated uploads
--    Operation: INSERT
--    Target roles: authenticated
-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Features 14–18
--  Run this block in the Supabase SQL Editor after the
--  initial setup above has already been executed.
-- ══════════════════════════════════════════════════════


-- ── MIGRATION 14: Add is_used to tickets ─────────────
--  Required for QR scanning (Feature 14).
--  Safe to run even if column already exists.

alter table tickets add column if not exists is_used boolean not null default false;

-- Admins need UPDATE access to mark tickets as used
create policy if not exists "Service role updates tickets"
    on tickets for update using (true);


-- ── 6. USER ROLES ─────────────────────────────────────
--  RBAC table — maps a user_id to a role string.
--  Roles: 'admin', 'judge'
--  Regular attendees have no row (no role).

create table if not exists user_roles (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    role       text not null check (role in ('admin', 'judge')),
    created_at timestamptz default now(),
    unique (user_id)          -- one role per user
);

alter table user_roles enable row level security;

-- Users can read their own role (so the app can check it client-side)
create policy "Users read own role"
    on user_roles for select using (auth.uid() = user_id);

-- Only the service_role / Supabase dashboard can assign roles
-- (no INSERT policy for anon/authenticated — admins assign via dashboard)


-- ── 7. SCORES ─────────────────────────────────────────
--  Judge scores per contestant.
--  Core constraint: one submission per (judge, contestant) pair.

create table if not exists scores (
    id                uuid primary key default gen_random_uuid(),
    judge_id          uuid not null references auth.users(id) on delete cascade,
    contestant_id     uuid not null references contestants(id) on delete cascade,
    catwalk_score     int  not null check (catwalk_score     between 0 and 25),
    originality_score int  not null check (originality_score between 0 and 25),
    confidence_score  int  not null check (confidence_score  between 0 and 25),
    outfit_score      int  not null check (outfit_score      between 0 and 25),
    total_score       int  not null check (total_score       between 0 and 100),
    created_at        timestamptz default now(),

    -- CRUCIAL: prevents a judge from scoring the same contestant twice
    unique (judge_id, contestant_id)
);

alter table scores enable row level security;

-- INSERT: only if the user has role = 'judge' in user_roles
create policy "Judges insert scores"
    on scores for insert
    with check (
        auth.uid() = judge_id
        and exists (
            select 1 from user_roles
            where user_id = auth.uid()
            and   role    = 'judge'
        )
    );

-- SELECT: judges AND admins can read ALL scores
--  (judges need cross-judge data to render the Live Rankings leaderboard)
create policy "Judges and admins read all scores"
    on scores for select
    using (
        exists (
            select 1 from user_roles
            where user_id = auth.uid()
            and   role    in ('judge', 'admin')
        )
    );


-- ── HOW TO ASSIGN A JUDGE OR ADMIN ROLE ───────────────
--
--  In the Supabase Dashboard → Table Editor → user_roles:
--  Click "Insert row" and fill in:
--    user_id : (UUID from auth.users — find it in Auth → Users)
--    role    : 'judge'  or  'admin'
--
--  Or run SQL directly:
--    insert into user_roles (user_id, role)
--    values ('paste-uuid-here', 'judge');
--
-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Feature 21: Judges read ALL scores
--  Run this block in the Supabase SQL Editor if the
--  database was already set up with the previous
--  "Judges read own scores" + "Admins read all scores"
--  policies.  This replaces them with a single policy
--  that lets both roles see all score rows.
-- ══════════════════════════════════════════════════════

-- Drop the two old policies (safe to run even if they
-- have already been removed or were never created)
drop policy if exists "Judges read own scores"    on scores;
drop policy if exists "Admins read all scores"    on scores;

-- Create the unified read policy for judges + admins
create policy if not exists "Judges and admins read all scores"
    on scores for select
    using (
        exists (
            select 1 from user_roles
            where user_id = auth.uid()
            and   role    in ('judge', 'admin')
        )
    );

-- Ensure authenticated users still have the GRANT (idempotent)
grant select on scores to authenticated;
-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Features 22–25
--  Paste this block into the Supabase SQL Editor and RUN.
--  Safe to run on an already-populated database.
-- ══════════════════════════════════════════════════════

-- ── Feature 22: Extra columns on contestants ──────────
alter table contestants add column if not exists age           int;
alter table contestants add column if not exists gender        text;
alter table contestants add column if not exists level         text;
alter table contestants add column if not exists clothing_size text;
alter table contestants add column if not exists shoe_size     numeric;
alter table contestants add column if not exists experience    text;
alter table contestants add column if not exists video_url     text;
alter table contestants add column if not exists payment_ref   text;

-- 30-contestant hard cap (fires BEFORE INSERT)
create or replace function enforce_contestant_cap()
returns trigger language plpgsql security definer as $$
begin
    if (select count(*) from contestants where payment_ref is not null) >= 30 then
        raise exception 'REGISTRATION_FULL';
    end if;
    return new;
end;
$$;

drop trigger if exists contestant_cap_trigger on contestants;
create trigger contestant_cap_trigger
    before insert on contestants
    for each row execute function enforce_contestant_cap();

-- Storage buckets (run in Supabase Dashboard → Storage if not yet created):
--   Name: contestant-videos   ✓ Public bucket
--   Allow authenticated uploads (INSERT policy)


-- ── Feature 23: Votes table + live results toggle ─────
create table if not exists votes (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid references auth.users(id) on delete cascade,
    category_id text not null,
    nominee_id  text not null,
    created_at  timestamptz default now(),
    unique (user_id, category_id)
);

alter table votes enable row level security;

drop policy if exists "votes_insert" on votes;
create policy "votes_insert"
    on votes for insert with check (auth.uid() = user_id);

drop policy if exists "votes_select" on votes;
create policy "votes_select"
    on votes for select using (true);

drop policy if exists "votes_update" on votes;
create policy "votes_update"
    on votes for update using (auth.uid() = user_id);

grant select, insert, update on votes to authenticated, anon;

-- Toggle columns on system_settings
alter table system_settings add column if not exists show_live_results boolean default false;
alter table system_settings add column if not exists lineup_revealed   boolean default false;

-- Allow admins to UPDATE system_settings
drop policy if exists "Admin update system_settings" on system_settings;
create policy "Admin update system_settings"
    on system_settings for update
    using (get_my_role() = 'admin');

-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Features 34–36: App-level control toggles
--  Adds three admin-controlled on/off switches to
--  system_settings so the admin panel can open/close
--  registration, nominations, and voting independently.
--  Safe to run on an already-populated database.
-- ══════════════════════════════════════════════════════

alter table system_settings add column if not exists is_registration_open boolean not null default true;
alter table system_settings add column if not exists is_nomination_open   boolean not null default true;
alter table system_settings add column if not exists is_voting_open       boolean not null default false;

-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Judging Panel: look-based scoring
--  Adds look_category (which runway segment is being
--  scored) and optional judge notes to the scores table.
--  Replaces the old unique(judge_id, contestant_id)
--  constraint with a three-column one so a judge can
--  submit separate scores per look.
--  Safe to run on an already-populated database.
-- ══════════════════════════════════════════════════════

alter table scores add column if not exists look_category text not null default 'professional';
alter table scores add column if not exists notes         text;

-- Drop the old two-column unique constraint (if it exists)
alter table scores drop constraint if exists scores_judge_id_contestant_id_key;

-- Add the new three-column unique constraint
-- (idempotent: the IF NOT EXISTS guard on ADD CONSTRAINT
--  is supported from PostgreSQL 9.x via DO block below)
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'scores_judge_contestant_look_unique'
    ) then
        alter table scores
            add constraint scores_judge_contestant_look_unique
            unique (judge_id, contestant_id, look_category);
    end if;
end;
$$;

-- Judges still need UPDATE to allow upserts via ON CONFLICT
drop policy if exists "Judges update own scores" on scores;
create policy "Judges update own scores"
    on scores for update
    using (
        auth.uid() = judge_id
        and exists (
            select 1 from user_roles
            where user_id = auth.uid()
            and   role    = 'judge'
        )
    );

-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Features 34–36: App-level control toggles
--  Adds three admin-controlled on/off switches to
--  system_settings so the admin panel can open/close
--  registration, nominations, and voting independently.
--  Safe to run on an already-populated database.
-- ══════════════════════════════════════════════════════

alter table system_settings add column if not exists is_registration_open boolean not null default true;
alter table system_settings add column if not exists is_nomination_open   boolean not null default true;
alter table system_settings add column if not exists is_voting_open       boolean not null default false;

-- ══════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════
--  MIGRATION — Judging Panel: look-based scoring
--  Adds look_category (which runway segment is being
--  scored) and optional judge notes to the scores table.
--  Replaces the old unique(judge_id, contestant_id)
--  constraint with a three-column one so a judge can
--  submit separate scores per look.
--  Safe to run on an already-populated database.
-- ══════════════════════════════════════════════════════

alter table scores add column if not exists look_category text not null default 'professional';
alter table scores add column if not exists notes         text;

-- Drop the old two-column unique constraint (if it exists)
alter table scores drop constraint if exists scores_judge_id_contestant_id_key;

-- Add the new three-column unique constraint
-- (wrapped in a DO block to make it idempotent)
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'scores_judge_contestant_look_unique'
    ) then
        alter table scores
            add constraint scores_judge_contestant_look_unique
            unique (judge_id, contestant_id, look_category);
    end if;
end;
$$;

-- Judges need UPDATE access for upserts (ON CONFLICT DO UPDATE)
drop policy if exists "Judges update own scores" on scores;
create policy "Judges update own scores"
    on scores for update
    using (
        auth.ui