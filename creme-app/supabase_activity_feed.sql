-- ═══════════════════════════════════════════════════════
--  Live feed rebuild: real, deletable rows + full auto-coverage
--  Run once in the Supabase SQL Editor.
--  Requires is_admin() from supabase_admin_contestants.sql.
-- ═══════════════════════════════════════════════════════
--  Previously the homepage feed was assembled live by querying
--  4 tables from the browser — there was no single row to delete.
--  activity_feed is now the one source the feed reads from, and
--  every entry in it is written automatically by a database
--  trigger the moment the underlying event happens (a dispatch is
--  posted, a contestant is featured, a photo is added, a challenge
--  opens or closes, a poll goes live, a sponsor/judge/team member
--  joins) — so it can never miss an update, no matter how the
--  change was made. Deleting a feed item only hides it from the
--  feed; the real record (photo, dispatch, etc.) is untouched.
--
--  Not included on purpose: individual ticket purchases, nominations,
--  votes and judge scores. Broadcasting who-paid-for-what or who
--  nominated whom to the whole site is a privacy call, not a wiring
--  decision — ask if you want any of those added as anonymous
--  aggregate milestones (e.g. "50 tickets sold!").

create table if not exists activity_feed (
    id         uuid primary key default gen_random_uuid(),
    kind       text not null,
    title      text,
    message    text not null,
    tag        text,
    image_url  text,
    link_tab   text,
    created_at timestamptz not null default now()
);
alter table activity_feed enable row level security;

drop policy if exists "Public read activity_feed" on activity_feed;
create policy "Public read activity_feed" on activity_feed
    for select using (true);

drop policy if exists "Admins delete activity_feed" on activity_feed;
create policy "Admins delete activity_feed" on activity_feed
    for delete to authenticated using (is_admin());
--  No insert/update policy — rows are only ever written by the
--  SECURITY DEFINER trigger functions below, never directly by users.

create or replace function log_activity(p_kind text, p_title text, p_message text, p_tag text, p_image text, p_link text)
returns void language plpgsql security definer set search_path = public as $$
begin
    insert into activity_feed(kind, title, message, tag, image_url, link_tab)
    values (p_kind, p_title, p_message, p_tag, p_image, p_link);
end;
$$;

-- ── Dispatches ──────────────────────────────────────────
create or replace function trg_log_dispatch() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('dispatch', new.headline, new.message, coalesce(new.tag,'announcement'), null, 'home');
    return new;
end;
$$;
drop trigger if exists on_dispatch_insert on dispatches;
create trigger on_dispatch_insert after insert on dispatches
    for each row execute function trg_log_dispatch();

-- ── Contestants: only when admin-featured (per earlier request) ──
create or replace function trg_log_contestant_featured() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.is_featured is true and (old.is_featured is distinct from true) then
        perform log_activity('contestant', new.full_name,
            new.full_name || ' just joined The Lineup' || case when new.department is not null then ' · ' || new.department else '' end,
            null, new.headshot_url, 'lineup');
    end if;
    return new;
end;
$$;
drop trigger if exists on_contestant_featured on contestants;
create trigger on_contestant_featured after update on contestants
    for each row execute function trg_log_contestant_featured();

-- ── Gallery ─────────────────────────────────────────────
create or replace function trg_log_gallery() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('gallery', null,
        case when new.caption is not null then '📸 New in the Gallery: ' || new.caption else '📸 New in the Gallery' end,
        null, new.image_url, 'gallery');
    return new;
end;
$$;
drop trigger if exists on_gallery_insert on gallery_media;
create trigger on_gallery_insert after insert on gallery_media
    for each row execute function trg_log_gallery();

-- ── Challenges: posted + closed/results ─────────────────
create or replace function trg_log_challenge() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('challenge', new.title,
        'New challenge: ' || new.title || case when new.marks is not null then ' · ' || new.marks::text || ' marks' else '' end,
        null, null, 'challenges');
    return new;
end;
$$;
drop trigger if exists on_challenge_insert on challenges;
create trigger on_challenge_insert after insert on challenges
    for each row execute function trg_log_challenge();

create or replace function trg_log_challenge_closed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.status = 'closed' and (old.status is distinct from 'closed') then
        perform log_activity('challenge_result', new.title, 'Results are in: ' || new.title, null, null, 'challenges');
    end if;
    return new;
end;
$$;
drop trigger if exists on_challenge_closed on challenges;
create trigger on_challenge_closed after update on challenges
    for each row execute function trg_log_challenge_closed();

-- ── Polls ───────────────────────────────────────────────
create or replace function trg_log_poll() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.is_active is true then
        perform log_activity('poll', new.title, '🗳️ New poll: ' || new.title || ' — have your say!', null, null, 'home');
    end if;
    return new;
end;
$$;
drop trigger if exists on_poll_insert on urgent_polls;
create trigger on_poll_insert after insert on urgent_polls
    for each row execute function trg_log_poll();

-- ── Sponsors ────────────────────────────────────────────
create or replace function trg_log_sponsor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('sponsor', new.name, '🤝 ' || new.name || ' just came on board as a sponsor!', null, new.logo_url, 'event');
    return new;
end;
$$;
drop trigger if exists on_sponsor_insert on sponsors;
create trigger on_sponsor_insert after insert on sponsors
    for each row execute function trg_log_sponsor();

-- ── Team members ────────────────────────────────────────
create or replace function trg_log_team() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('team', new.name, '👥 ' || new.name || ' joined the organizing team', null, new.photo_url, 'team');
    return new;
end;
$$;
drop trigger if exists on_team_insert on team_members;
create trigger on_team_insert after insert on team_members
    for each row execute function trg_log_team();

-- ── Judges ──────────────────────────────────────────────
create or replace function trg_log_judge() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    perform log_activity('judge', new.name, '⚖️ ' || new.name || ' announced as a judge', null, new.photo_url, 'judges');
    return new;
end;
$$;
drop trigger if exists on_judge_insert on judges;
create trigger on_judge_insert after insert on judges
    for each row execute function trg_log_judge();
