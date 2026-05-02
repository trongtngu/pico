drop function if exists public.create_focus_session(text, integer);
drop function if exists public.join_focus_session(uuid);

create table public.user_fish_catches (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    catch_index integer not null,
    sea_critter_id text not null references public.sea_critters(id),
    rarity text not null,
    sell_value bigint not null,
    caught_at timestamptz not null default now(),
    sold_at timestamptz,
    sold_for_berries bigint,
    constraint user_fish_catches_catch_index_valid
        check (catch_index between 1 and 3),
    constraint user_fish_catches_user_session_catch_unique
        unique (user_id, session_id, catch_index),
    constraint user_fish_catches_rarity_valid
        check (rarity in ('common', 'rare', 'ultra_rare')),
    constraint user_fish_catches_sell_value_positive
        check (sell_value > 0),
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

create policy "Users can read own fish catches"
on public.user_fish_catches
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_fish_catches from public, anon, authenticated;
grant select on public.user_fish_catches to authenticated;

create function public.random_fish_catches(island_id text default 'default')
returns table (
    catch_index integer,
    sea_critter_id text,
    rarity text,
    sell_value bigint
)
security definer
set search_path = public
language plpgsql
as $$
declare
    draw_index integer;
    draw_weight numeric;
    selected_island_id text := coalesce(nullif(lower(btrim($1)), ''), 'default');
    selected_critter record;
    total_weight numeric;
begin
    if not exists (
        select 1
        from public.islands
        where islands.id = selected_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', selected_island_id using errcode = 'P0002';
    end if;

    select coalesce(sum(sea_critters.drop_weight), 0)
    into total_weight
    from public.island_sea_critters
    join public.sea_critters
        on sea_critters.id = island_sea_critters.sea_critter_id
    where island_sea_critters.island_id = selected_island_id
        and island_sea_critters.is_enabled
        and sea_critters.is_enabled
        and sea_critters.drop_weight > 0;

    if total_weight <= 0 then
        raise exception 'No enabled sea critters with positive drop weight are available for island %.', selected_island_id using errcode = 'P0002';
    end if;

    for draw_index in 1..3 loop
        draw_weight := random()::numeric * total_weight;

        select
            weighted_critters.id,
            weighted_critters.rarity,
            weighted_critters.sell_value
        into selected_critter
        from (
            select
                sea_critters.id,
                sea_critters.rarity,
                sea_critters.sell_value,
                sum(sea_critters.drop_weight) over (
                    order by sea_critters.sort_order, sea_critters.id
                ) as cumulative_weight
            from public.island_sea_critters
            join public.sea_critters
                on sea_critters.id = island_sea_critters.sea_critter_id
            where island_sea_critters.island_id = selected_island_id
                and island_sea_critters.is_enabled
                and sea_critters.is_enabled
                and sea_critters.drop_weight > 0
        ) weighted_critters
        where weighted_critters.cumulative_weight > draw_weight
        order by weighted_critters.cumulative_weight
        limit 1;

        catch_index := draw_index;
        sea_critter_id := selected_critter.id;
        rarity := selected_critter.rarity;
        sell_value := selected_critter.sell_value;

        return next;
    end loop;
end;
$$;

create function public.create_focus_session_fish_catches(
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
    selected_island_id text;
begin
    select session_members.island_id
    into selected_island_id
    from public.session_members
    join public.islands
        on islands.id = session_members.island_id
        and islands.is_enabled
    where session_members.session_id = target_session_id
        and session_members.user_id = completing_user_id
        and session_members.status = 'joined';

    if selected_island_id is null then
        raise exception 'No enabled island is stored for user % in focus session %.', completing_user_id, target_session_id using errcode = 'P0002';
    end if;

    insert into public.user_fish_catches (
        user_id,
        session_id,
        catch_index,
        sea_critter_id,
        rarity,
        sell_value,
        caught_at
    )
    select
        completing_user_id,
        target_session_id,
        random_fish_catches.catch_index,
        random_fish_catches.sea_critter_id,
        random_fish_catches.rarity,
        random_fish_catches.sell_value,
        catch_time
    from public.random_fish_catches(selected_island_id)
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

comment on column public.session_members.island_id is
    'Per-user fishing island captured when the member creates or joins the focus session. Fish rewards use this value for the completing member.';

comment on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) is
    'Creates fish catches using session_members.island_id for the completing user and target session.';

create function public.validate_session_member_island()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.island_id is null then
        raise exception 'Session member island cannot be null.' using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = new.island_id
            and islands.is_enabled
    ) then
        raise exception 'Session member island % is not enabled or does not exist.', new.island_id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger validate_session_member_island
before insert or update of island_id
on public.session_members
for each row
execute function public.validate_session_member_island();

create function public.prevent_disabling_session_member_island()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if old.is_enabled
        and not new.is_enabled
        and exists (
            select 1
            from public.session_members
            join public.focus_sessions
                on focus_sessions.id = session_members.session_id
            where session_members.island_id = old.id
                and session_members.status = 'joined'
                and focus_sessions.status in ('lobby', 'launched', 'live')
        )
    then
        raise exception 'Island % cannot be disabled while active focus session members reference it.', old.id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger prevent_disabling_session_member_island
before update of is_enabled
on public.islands
for each row
execute function public.prevent_disabling_session_member_island();

create function public.create_focus_session(
    session_mode text default 'solo',
    duration_seconds integer default 1800,
    island_id text default 'default'
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    new_session_id uuid;
    normalized_island_id text := coalesce(nullif(lower(btrim(island_id)), ''), 'default');
    normalized_mode text := lower(btrim(session_mode));
begin
    if requester is null then
        raise exception 'You must be signed in to create a focus session.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));
    perform public.reconcile_open_focus_sessions();

    if normalized_mode is null or normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 10 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 seconds and 24 hours.' using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = normalized_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', normalized_island_id using errcode = '22023';
    end if;

    if exists (
        select 1
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and (
                focus_sessions.status = 'lobby'
                or (
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                    and focus_sessions.planned_end_at > now()
                    and not exists (
                        select 1
                        from public.session_events
                        where session_events.session_id = focus_sessions.id
                            and session_events.user_id = requester
                            and session_events.event_type in ('member_completed', 'member_interrupted')
                    )
                )
            )
    ) then
        raise exception 'You already have an open focus session.' using errcode = '23505';
    end if;

    insert into public.focus_sessions (
        owner_id,
        mode,
        duration_seconds
    )
    values (
        requester,
        normalized_mode,
        duration_seconds
    )
    returning id into new_session_id;

    insert into public.session_members (
        session_id,
        user_id,
        island_id,
        role,
        status
    )
    values (
        new_session_id,
        requester,
        normalized_island_id,
        'host',
        'joined'
    );

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
end;
$$;

create function public.join_focus_session(target_session_id uuid, island_id text default 'default')
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_island_id text := coalesce(nullif(lower(btrim(island_id)), ''), 'default');
    session_record public.focus_sessions%rowtype;
    membership_record public.session_members%rowtype;
    joined_now boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to join a focus session.' using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = normalized_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', normalized_island_id using errcode = '22023';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    select *
    into membership_record
    from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status in ('invited', 'joined', 'left')
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if session_record.status = 'cancelled' then
        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined');

        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    if membership_record.status = 'invited' then
        update public.session_members
        set status = 'joined',
            island_id = normalized_island_id
        where session_id = target_session_id
            and user_id = requester
            and status = 'invited';

        joined_now := found;
    end if;

    if membership_record.status <> 'joined' and not joined_now then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if joined_now then
        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_joined');
    end if;

    return public.focus_session_payload(target_session_id);
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

create function public.sell_user_fish(catch_ids uuid[])
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    sold_fish_count integer,
    sold_berry_amount bigint
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    sold_time timestamptz := now();
    requested_count integer;
    distinct_requested_count integer;
    locked_count integer;
    already_sold_count integer;
    sold_amount bigint := 0;
    sold_count integer := 0;
    updated_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to sell fish.' using errcode = '28000';
    end if;

    requested_count := coalesce(cardinality(catch_ids), 0);
    if requested_count = 0 then
        raise exception 'Choose at least one fish to sell.' using errcode = '22023';
    end if;

    select count(distinct requested_catch_id)
    into distinct_requested_count
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    if distinct_requested_count <> requested_count then
        raise exception 'Fish can only be sold once per request.' using errcode = '22023';
    end if;

    drop table if exists pg_temp.requested_fish_sale_ids;
    drop table if exists pg_temp.locked_fish_sale_rows;

    create temporary table requested_fish_sale_ids (
        id uuid primary key
    ) on commit drop;

    insert into requested_fish_sale_ids (id)
    select requested_catch_id
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    create temporary table locked_fish_sale_rows
    on commit drop
    as
    select user_fish_catches.*
    from public.user_fish_catches
    join requested_fish_sale_ids
        on requested_fish_sale_ids.id = user_fish_catches.id
    where user_fish_catches.user_id = requester
    for update of user_fish_catches;

    select count(*)
    into locked_count
    from locked_fish_sale_rows;

    if locked_count <> requested_count then
        raise exception 'One or more selected fish could not be found.' using errcode = 'P0002';
    end if;

    select count(*)
    into already_sold_count
    from locked_fish_sale_rows
    where sold_at is not null;

    if already_sold_count > 0 then
        raise exception 'One or more selected fish has already been sold.' using errcode = '23514';
    end if;

    with sold_rows as (
        update public.user_fish_catches
        set sold_at = sold_time,
            sold_for_berries = public.user_fish_catches.sell_value
        from requested_fish_sale_ids
        where public.user_fish_catches.id = requested_fish_sale_ids.id
            and public.user_fish_catches.user_id = requester
            and public.user_fish_catches.sold_at is null
        returning public.user_fish_catches.sell_value
    )
    select
        count(*)::integer,
        coalesce(sum(sell_value), 0)::bigint
    into sold_count, sold_amount
    from sold_rows;

    if sold_count <> requested_count then
        raise exception 'One or more selected fish could not be sold.' using errcode = '40001';
    end if;

    insert into public.user_berry_balances (user_id, berries)
    values (requester, sold_amount)
    on conflict (user_id) do update
    set berries = public.user_berry_balances.berries + excluded.berries
    returning *
    into updated_balance;

    return query
    select
        updated_balance.berries,
        updated_balance.completion_streak,
        updated_balance.last_completed_on,
        updated_balance.last_completed_at,
        sold_count,
        sold_amount;
end;
$$;

create function public.fetch_user_fish_collection_counts(island_id text default 'default')
returns table (
    sea_critter_id text,
    display_name text,
    rarity text,
    sell_value bigint,
    asset_name text,
    sort_order integer,
    count integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    selected_island_id text := coalesce(nullif(lower(btrim($1)), ''), 'default');
begin
    if requester is null then
        raise exception 'You must be signed in to view fish collection counts.' using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = selected_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', selected_island_id using errcode = 'P0002';
    end if;

    return query
    select
        sea_critters.id as sea_critter_id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order,
        count(user_fish_catches.id)::integer as count
    from public.island_sea_critters
    join public.sea_critters
        on sea_critters.id = island_sea_critters.sea_critter_id
    left join public.user_fish_catches
        on user_fish_catches.sea_critter_id = sea_critters.id
        and user_fish_catches.user_id = requester
    where island_sea_critters.island_id = selected_island_id
        and island_sea_critters.is_enabled
        and sea_critters.is_enabled
    group by
        sea_critters.id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order
    order by sea_critters.sort_order;
end;
$$;

create function public.fetch_user_fish_inventory_counts()
returns table (
    sea_critter_id text,
    display_name text,
    rarity text,
    sell_value bigint,
    asset_name text,
    sort_order integer,
    count integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to view fish inventory counts.' using errcode = '28000';
    end if;

    return query
    select
        sea_critters.id as sea_critter_id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order,
        count(user_fish_catches.id)::integer as count
    from public.user_fish_catches
    join public.sea_critters
        on sea_critters.id = user_fish_catches.sea_critter_id
    where user_fish_catches.user_id = requester
        and user_fish_catches.sold_at is null
    group by
        sea_critters.id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order
    order by sea_critters.sort_order;
end;
$$;

comment on function public.fetch_user_fish_inventory_counts() is
    'Returns owned unsold fish counts for inventory/selling only. This is intentionally not island-scoped and must not be used for catalog, collection, or reward eligibility.';

revoke all on function public.random_fish_catches(text) from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.validate_session_member_island() from public, anon, authenticated;
revoke all on function public.prevent_disabling_session_member_island() from public, anon, authenticated;
revoke all on function public.create_focus_session(text, integer, text) from public, anon, authenticated;
revoke all on function public.join_focus_session(uuid, text) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;
revoke all on function public.sell_user_fish(uuid[]) from public, anon, authenticated;
revoke all on function public.fetch_user_fish_collection_counts(text) from public, anon, authenticated;
revoke all on function public.fetch_user_fish_inventory_counts() from public, anon, authenticated;

grant execute on function public.create_focus_session(text, integer, text) to authenticated;
grant execute on function public.join_focus_session(uuid, text) to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;
grant execute on function public.sell_user_fish(uuid[]) to authenticated;
grant execute on function public.fetch_user_fish_collection_counts(text) to authenticated;
grant execute on function public.fetch_user_fish_inventory_counts() to authenticated;

do $$
declare
    invalid_count integer;
begin
    select count(*)
    into invalid_count
    from public.session_members
    left join public.islands
        on islands.id = session_members.island_id
        and islands.is_enabled
    where islands.id is null;

    if invalid_count > 0 then
        raise exception 'All session members must reference an enabled island; found % invalid rows.', invalid_count;
    end if;
end $$;

notify pgrst, 'reload schema';
