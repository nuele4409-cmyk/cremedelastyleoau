-- ═══════════════════════════════════════════════════════
--  Live feed v2: ticket social-proof + section open/close
--  Run once in the Supabase SQL Editor, after
--  supabase_activity_feed.sql.
-- ═══════════════════════════════════════════════════════

-- ── Ticket purchases: "Ade and 20 others just purchased a
--    VIP ticket" style social proof. Fires the moment a ticket
--    actually becomes paid (Flutterwave verification, or the
--    admin manual-override fallback) — never on the initial
--    pending row, so nobody sees a purchase before it clears. ──
create or replace function trg_log_ticket_paid() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    buyer_name text;
    other_count int;
    msg text;
begin
    if new.payment_status = 'paid' and (tg_op = 'INSERT' or old.payment_status is distinct from 'paid') then
        select coalesce(nullif(trim(raw_user_meta_data->>'full_name'), ''), split_part(email, '@', 1))
          into buyer_name
          from auth.users where id = new.user_id;

        select count(*) into other_count from tickets
          where tier_name = new.tier_name and payment_status = 'paid';
        other_count := greatest(other_count - 1, 0);

        msg := coalesce(buyer_name, 'Someone')
             || case when other_count > 0
                    then ' and ' || other_count || case when other_count = 1 then ' other' else ' others' end
                    else ''
                end
             || ' just purchased a ' || new.tier_name || ' ticket 🎟️';

        perform log_activity('ticket', null, msg, null, null, 'tickets');
    end if;
    return new;
end;
$$;
drop trigger if exists on_ticket_paid on tickets;
create trigger on_ticket_paid after insert or update on tickets
    for each row execute function trg_log_ticket_paid();

-- ── Section open/close announcements from the admin's Master
--    App Controls panel (Registration, Nominations, Voting,
--    Tickets, Judges/Team/Lineup reveal, Volunteer signups). ──
create or replace function trg_log_app_controls() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if new.is_registration_open is distinct from old.is_registration_open then
        perform log_activity('control', null, case when new.is_registration_open
            then '📝 Contestant Registration is now OPEN!' else '📝 Contestant Registration is now closed.' end,
            null, null, 'register');
    end if;
    if new.is_nomination_open is distinct from old.is_nomination_open then
        perform log_activity('control', null, case when new.is_nomination_open
            then '✨ Nominations are now OPEN — go nominate!' else '✨ Nominations are now closed.' end,
            null, null, 'nominate');
    end if;
    if new.is_voting_open is distinct from old.is_voting_open then
        perform log_activity('control', null, case when new.is_voting_open
            then '🗳️ Fan Favourite Voting is now OPEN!' else '🗳️ Voting is now closed.' end,
            null, null, 'vote');
    end if;
    if new.show_tickets is distinct from old.show_tickets then
        perform log_activity('control', null, case when new.show_tickets
            then '🎟️ Ticket sales are now OPEN!' else '🎟️ Ticket sales are now closed.' end,
            null, null, 'tickets');
    end if;
    if new.show_lineup is distinct from old.show_lineup then
        perform log_activity('control', null, case when new.show_lineup
            then '👗 The Lineup has been revealed!' else '👗 The Lineup is hidden for now.' end,
            null, null, 'lineup');
    end if;
    if new.show_judges is distinct from old.show_judges then
        perform log_activity('control', null, case when new.show_judges
            then '⚖️ Meet the Judges — now revealed!' else '⚖️ Judges panel is hidden for now.' end,
            null, null, 'judges');
    end if;
    if new.show_team is distinct from old.show_team then
        perform log_activity('control', null, case when new.show_team
            then '👥 Meet the Team — now revealed!' else '👥 Team page is hidden for now.' end,
            null, null, 'team');
    end if;
    if new.show_volunteer is distinct from old.show_volunteer then
        perform log_activity('control', null, case when new.show_volunteer
            then '🙋 Volunteer signups are now OPEN!' else '🙋 Volunteer signups are now closed.' end,
            null, null, 'volunteer');
    end if;
    return new;
end;
$$;
drop trigger if exists on_app_controls_update on system_settings;
create trigger on_app_controls_update after update on system_settings
    for each row execute function trg_log_app_controls();
