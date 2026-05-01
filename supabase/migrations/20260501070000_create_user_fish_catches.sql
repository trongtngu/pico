create table public.user_fish_catches (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    catch_index integer not null,
    fish_type text not null,
    rarity text not null,
    sell_value bigint not null,
    caught_at timestamptz not null default now(),
    sold_at timestamptz,
    sold_for_berries bigint,
    constraint user_fish_catches_catch_index_valid
        check (catch_index between 1 and 3),
    constraint user_fish_catches_user_session_catch_unique
        unique (user_id, session_id, catch_index),
    constraint user_fish_catches_fish_type_valid
        check (fish_type in ('bass', 'salmon', 'tuna')),
    constraint user_fish_catches_rarity_valid
        check (rarity in ('common', 'uncommon', 'rare')),
    constraint user_fish_catches_fish_value_matches_type
        check (
            (fish_type = 'bass' and rarity = 'common' and sell_value = 1)
            or (fish_type = 'salmon' and rarity = 'uncommon' and sell_value = 2)
            or (fish_type = 'tuna' and rarity = 'rare' and sell_value = 3)
        ),
    constraint user_fish_catches_sold_state_valid
        check (
            (sold_at is null and sold_for_berries is null)
            or (sold_at is not null and sold_for_berries is not null)
        ),
    constraint user_fish_catches_sold_for_berries_positive
        check (sold_for_berries is null or sold_for_berries > 0)
);

create index user_fish_catches_user_caught_at_idx
on public.user_fish_catches (user_id, caught_at desc);

create index user_fish_catches_user_unsold_idx
on public.user_fish_catches (user_id, caught_at desc)
where sold_at is null;

create index user_fish_catches_session_user_idx
on public.user_fish_catches (session_id, user_id);

alter table public.user_fish_catches enable row level security;

drop policy if exists "Users can read own fish catches" on public.user_fish_catches;
create policy "Users can read own fish catches"
on public.user_fish_catches
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_fish_catches from anon, authenticated;
grant select on public.user_fish_catches to authenticated;

create or replace function public.random_fish_catches()
returns table (
    catch_index integer,
    fish_type text,
    rarity text,
    sell_value bigint
)
security definer
set search_path = public
language plpgsql
as $$
declare
    draw_index integer;
    roll double precision;
begin
    for draw_index in 1..3 loop
        catch_index := draw_index;
        roll := random();

        if roll < 0.04 then
            fish_type := 'tuna';
            rarity := 'rare';
            sell_value := 3;
        elsif roll < 0.20 then
            fish_type := 'salmon';
            rarity := 'uncommon';
            sell_value := 2;
        else
            fish_type := 'bass';
            rarity := 'common';
            sell_value := 1;
        end if;

        return next;
    end loop;
end;
$$;

create or replace function public.create_focus_session_fish_catches(
    completing_user_id uuid,
    target_session_id uuid,
    caught_at timestamptz default now()
)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
    catch_time timestamptz := caught_at;
begin
    insert into public.user_fish_catches (
        user_id,
        session_id,
        catch_index,
        fish_type,
        rarity,
        sell_value,
        caught_at
    )
    select
        completing_user_id,
        target_session_id,
        random_fish_catches.catch_index,
        random_fish_catches.fish_type,
        random_fish_catches.rarity,
        random_fish_catches.sell_value,
        catch_time
    from public.random_fish_catches()
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

create or replace function public.complete_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    finished_at timestamptz := now();
    completion_recorded_at timestamptz;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to complete a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and (
            status in ('live', 'completed')
            or (mode = 'multiplayer' and status = 'launched')
        )
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined'
    ) then
        raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'multiplayer' and exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_interrupted'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.record_user_completion_streak(
            requester,
            completion_recorded_at
        );

        perform public.create_focus_session_fish_catches(
            requester,
            target_session_id,
            completion_recorded_at
        );

        perform public.award_villager_completion_pairs(
            target_session_id,
            requester,
            completion_recorded_at
        );
    end if;

    if session_record.status = 'live' and session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.reconcile_open_focus_sessions()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    reconciled_at timestamptz := now();
    stale_lobby_after interval := interval '24 hours';
    session_record record;
    completion_recorded_at timestamptz;
    completed_count integer := 0;
    cancelled_lobby_count integer := 0;
    left_lobby_count integer := 0;
    repaired_cancelled_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to reconcile focus sessions.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));

    update public.session_members
    set status = 'left'
    from public.focus_sessions
    where session_members.session_id = focus_sessions.id
        and session_members.user_id = requester
        and session_members.status in ('invited', 'joined')
        and focus_sessions.status = 'cancelled';

    get diagnostics repaired_cancelled_count = row_count;
    cancelled_lobby_count := cancelled_lobby_count + repaired_cancelled_count;

    for session_record in
        select
            focus_sessions.*,
            session_members.role as member_role
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.status = 'lobby'
            and focus_sessions.updated_at <= reconciled_at - stale_lobby_after
        for update of focus_sessions
    loop
        if session_record.owner_id = requester or session_record.member_role = 'host' then
            update public.focus_sessions
            set status = 'cancelled',
                ended_at = reconciled_at
            where id = session_record.id
                and status = 'lobby';

            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and status in ('invited', 'joined');

            cancelled_lobby_count := cancelled_lobby_count + 1;
        else
            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and user_id = requester
                and status = 'joined';

            left_lobby_count := left_lobby_count + 1;
        end if;
    end loop;

    for session_record in
        select focus_sessions.*
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.planned_end_at <= reconciled_at
            and (
                (
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                )
            )
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = focus_sessions.id
                    and session_events.user_id = requester
                    and session_events.event_type in ('member_completed', 'member_interrupted')
            )
        for update of focus_sessions
    loop
        completion_recorded_at := null;

        insert into public.session_events (session_id, user_id, event_type)
        values (session_record.id, requester, 'member_completed')
        on conflict do nothing
        returning occurred_at into completion_recorded_at;

        if completion_recorded_at is not null then
            perform public.record_user_completion_streak(
                requester,
                completion_recorded_at
            );

            perform public.create_focus_session_fish_catches(
                requester,
                session_record.id,
                completion_recorded_at
            );

            perform public.award_villager_completion_pairs(
                session_record.id,
                requester,
                completion_recorded_at
            );
        end if;

        if session_record.mode = 'solo' then
            update public.focus_sessions
            set status = 'completed',
                ended_at = greatest(reconciled_at, planned_end_at)
            where id = session_record.id
                and status = 'live';
        end if;

        completed_count := completed_count + 1;
    end loop;

    return jsonb_build_object(
        'reconciled_at', reconciled_at,
        'completed_sessions', completed_count,
        'cancelled_lobbies', cancelled_lobby_count,
        'left_lobbies', left_lobby_count
    );
end;
$$;

revoke all on function public.random_fish_catches() from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;

grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;

notify pgrst, 'reload schema';
