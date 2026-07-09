-- ═══════════════════════════════════════════════════════
--  Push notifications: every live feed update lands in the
--  user's phone notification bar, not just in-app.
--  Run once in the Supabase SQL Editor, AFTER deploying the
--  send-push Edge Function and setting its 3 VAPID secrets.
-- ═══════════════════════════════════════════════════════
--  How it works: the browser registers a "push subscription"
--  per device (stored below), and the instant a new row lands
--  in activity_feed, a trigger here fires the send-push Edge
--  Function via pg_net — which pushes to every subscribed
--  device using Web Push (VAPID). No polling, no manual step.

create table if not exists push_subscriptions (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid references auth.users(id) on delete cascade,
    endpoint   text not null unique,
    p256dh     text not null,
    auth_key   text not null,
    created_at timestamptz default now()
);
alter table push_subscriptions enable row level security;

drop policy if exists "Users manage own push subscription" on push_subscriptions;
create policy "Users manage own push subscription" on push_subscriptions
    for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
--  The send-push function reads this table with the service_role
--  key, which bypasses RLS entirely — no separate "admin read all"
--  policy is needed for sending.

--  RLS policies alone aren't enough — Postgres also needs the
--  underlying table GRANT, which the SQL Editor doesn't add
--  automatically (see supabase_fix_permissions.sql for the same
--  issue on other tables from this session).
grant select, insert, update, delete on push_subscriptions to authenticated;

create extension if not exists pg_net with schema extensions;

create or replace function trg_push_activity_feed() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
    perform net.http_post(
        url     := 'https://nfoeltjcmemcpwdwewbq.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mb2VsdGpjbWVtY3B3ZHdld2JxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1Nzc5MDgsImV4cCI6MjA5NTE1MzkwOH0.YIp_5dRhsSYCdwpNy51RRqmKtzx4qZY5yHXfbBlnxMk',
            'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mb2VsdGpjbWVtY3B3ZHdld2JxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1Nzc5MDgsImV4cCI6MjA5NTE1MzkwOH0.YIp_5dRhsSYCdwpNy51RRqmKtzx4qZY5yHXfbBlnxMk'
        ),
        body    := jsonb_build_object(
            'title', coalesce(new.title, 'Crème De La Style'),
            'body', new.message,
            'link_tab', new.link_tab,
            'image_url', new.image_url
        )
    );
    return new;
end;
$$;
drop trigger if exists on_activity_feed_push on activity_feed;
create trigger on_activity_feed_push after insert on activity_feed
    for each row execute function trg_push_activity_feed();
