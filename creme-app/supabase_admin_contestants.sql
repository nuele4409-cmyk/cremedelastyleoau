-- ═══════════════════════════════════════════════════════
--  July 2026 updates — run once in the Supabase SQL Editor
--  (pre-event countdown, free tickets, admin add/delete contestants)
-- ═══════════════════════════════════════════════════════

-- ── 1. Pre-event date for the homepage countdown ──────────
--  The countdown targets this first; after it passes it rolls
--  over to event_date automatically. Edit it here any time.
alter table system_settings add column if not exists pre_event_date timestamptz;
update system_settings set pre_event_date = '2026-08-01T19:00:00+01:00' where pre_event_date is null;

-- ── 2. Ticket security ─────────────────────────────────────
--  Free (₦0) tickets may be created as 'paid' directly, but any
--  ticket that costs money is forced to 'pending' on insert —
--  only the verify-flw-payment Edge Function can mark it paid.
create or replace function force_pending_on_paid_tickets()
returns trigger language plpgsql as $$
begin
    if new.amount > 0 then
        new.payment_status := 'pending';
    end if;
    return new;
end;
$$;
drop trigger if exists trg_force_pending_tickets on tickets;
create trigger trg_force_pending_tickets
    before insert on tickets
    for each row execute function force_pending_on_paid_tickets();

--  One free General Entry ticket per user
create unique index if not exists one_free_ticket_per_user
    on tickets (user_id) where (tier_name = 'General Entry');

-- ── 3. Admins can manually add and delete contestants ──────
drop policy if exists "Admins insert contestants" on contestants;
create policy "Admins insert contestants" on contestants
    for insert to authenticated
    with check (exists (select 1 from user_roles where user_id = auth.uid() and role = 'admin'));

drop policy if exists "Admins delete contestants" on contestants;
create policy "Admins delete contestants" on contestants
    for delete to authenticated
    using (exists (select 1 from user_roles where user_id = auth.uid() and role = 'admin'));
