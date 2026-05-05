alter table public.user_fish_catches
    drop constraint if exists user_fish_catches_catch_index_valid;

alter table public.user_fish_catches
    add constraint user_fish_catches_catch_index_valid
        check (catch_index between 1 and 12);

drop function if exists public.random_fish_catches(text);

create function public.random_fish_catches(
    island_id text default 'default',
    catch_count integer default 3
)
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
    selected_catch_count integer := coalesce($2, 3);
    selected_critter record;
    total_weight numeric;
begin
    if selected_catch_count < 1 or selected_catch_count > 12 then
        raise exception 'Fish catch count % is outside the supported range.', selected_catch_count using errcode = '22023';
    end if;

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

    for draw_index in 1..selected_catch_count loop
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
    selected_island_id text;
    session_duration_seconds integer;
    catch_count integer;
begin
    select
        session_members.island_id,
        focus_sessions.duration_seconds
    into
        selected_island_id,
        session_duration_seconds
    from public.session_members
    join public.focus_sessions
        on focus_sessions.id = session_members.session_id
    join public.islands
        on islands.id = session_members.island_id
        and islands.is_enabled
    where session_members.session_id = target_session_id
        and session_members.user_id = completing_user_id
        and session_members.status = 'joined';

    if selected_island_id is null then
        raise exception 'No enabled island is stored for user % in focus session %.', completing_user_id, target_session_id using errcode = 'P0002';
    end if;

    catch_count := case
        when session_duration_seconds >= 90 * 60 then 12
        when session_duration_seconds >= 60 * 60 then 9
        when session_duration_seconds >= 45 * 60 then 7
        when session_duration_seconds >= 30 * 60 then 5
        when session_duration_seconds >= 20 * 60 then 4
        else 3
    end;

    -- Rarity bonuses are intentionally not applied here. This migration only
    -- makes the number of catches duration-aware; rarity bonuses belong in a
    -- follow-up migration so weighted island selection remains unchanged.
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
    from public.random_fish_catches(selected_island_id, catch_count)
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

comment on function public.random_fish_catches(text, integer) is
    'Generates weighted fish catches for an island. Catch count is duration-aware, while rarity bonuses are intentionally left for a follow-up migration.';

comment on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) is
    'Creates duration-aware fish catches using session_members.island_id for the completing user and target session. Rarity bonuses are intentionally left for a follow-up migration.';

revoke all on function public.random_fish_catches(text, integer) from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;

notify pgrst, 'reload schema';
