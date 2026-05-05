create or replace function public.random_fish_catches_with_rarity_bonus(
    island_id text,
    catch_count integer,
    duration_seconds integer
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
    small_rare_bonus_probability constant numeric := 0.15;
    ultra_rare_bonus_weight_multiplier constant numeric := 2.0;
    draw_index integer;
    draw_weight numeric;
    draw_total_weight numeric;
    selected_island_id text := coalesce(nullif(lower(btrim($1)), ''), 'default');
    selected_catch_count integer := coalesce($2, 3);
    selected_duration_seconds integer := coalesce($3, 0);
    selected_critter record;
    total_weight numeric;
    rare_pool_total_weight numeric;
    boosted_rare_pool_total_weight numeric;
    bonus_catch_index integer;
    bonus_mode text := 'none';
    use_rare_pool boolean;
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

    select
        coalesce(sum(sea_critters.drop_weight), 0),
        coalesce(sum(
            case
                when sea_critters.rarity = 'ultra_rare' then sea_critters.drop_weight * ultra_rare_bonus_weight_multiplier
                else sea_critters.drop_weight
            end
        ), 0)
    into
        rare_pool_total_weight,
        boosted_rare_pool_total_weight
    from public.island_sea_critters
    join public.sea_critters
        on sea_critters.id = island_sea_critters.sea_critter_id
    where island_sea_critters.island_id = selected_island_id
        and island_sea_critters.is_enabled
        and sea_critters.is_enabled
        and sea_critters.drop_weight > 0
        and sea_critters.rarity in ('rare', 'ultra_rare');

    if selected_duration_seconds >= 90 * 60 then
        bonus_mode := 'guaranteed_ultra_boost';
    elsif selected_duration_seconds >= 60 * 60 then
        bonus_mode := 'guaranteed';
    elsif selected_duration_seconds >= 30 * 60 then
        bonus_mode := 'small_chance';
    end if;

    if bonus_mode <> 'none' then
        bonus_catch_index := floor(random() * selected_catch_count)::integer + 1;
    end if;

    for draw_index in 1..selected_catch_count loop
        use_rare_pool := false;

        -- Bonus policy:
        -- - 30-59 minutes picks one bonus-influenced draw and has a 15% chance
        --   to upgrade that draw into the island's rare-or-better pool.
        -- - 60-89 minutes guarantees that one draw uses the rare-or-better pool.
        -- - 90+ minutes also guarantees one rare-or-better draw, and only that
        --   draw doubles ultra_rare weight to improve ultra rare odds.
        -- If the selected island has no enabled rare-or-better critter with
        -- positive drop weight, the bonus draw falls back to the normal island
        -- weighted draw instead of failing.
        if draw_index = bonus_catch_index and rare_pool_total_weight > 0 then
            if bonus_mode in ('guaranteed', 'guaranteed_ultra_boost') then
                use_rare_pool := true;
            elsif bonus_mode = 'small_chance' and random()::numeric < small_rare_bonus_probability then
                use_rare_pool := true;
            end if;
        end if;

        if use_rare_pool then
            draw_total_weight := case
                when bonus_mode = 'guaranteed_ultra_boost' then boosted_rare_pool_total_weight
                else rare_pool_total_weight
            end;
            draw_weight := random()::numeric * draw_total_weight;

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
                    sum(
                        case
                            when bonus_mode = 'guaranteed_ultra_boost'
                                and sea_critters.rarity = 'ultra_rare'
                                then sea_critters.drop_weight * ultra_rare_bonus_weight_multiplier
                            else sea_critters.drop_weight
                        end
                    ) over (
                        order by sea_critters.sort_order, sea_critters.id
                    ) as cumulative_weight
                from public.island_sea_critters
                join public.sea_critters
                    on sea_critters.id = island_sea_critters.sea_critter_id
                where island_sea_critters.island_id = selected_island_id
                    and island_sea_critters.is_enabled
                    and sea_critters.is_enabled
                    and sea_critters.drop_weight > 0
                    and sea_critters.rarity in ('rare', 'ultra_rare')
            ) weighted_critters
            where weighted_critters.cumulative_weight > draw_weight
            order by weighted_critters.cumulative_weight
            limit 1;
        else
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
        end if;

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
        random_fish_catches_with_rarity_bonus.catch_index,
        random_fish_catches_with_rarity_bonus.sea_critter_id,
        random_fish_catches_with_rarity_bonus.rarity,
        random_fish_catches_with_rarity_bonus.sell_value,
        catch_time
    from public.random_fish_catches_with_rarity_bonus(
        selected_island_id,
        catch_count,
        session_duration_seconds
    )
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

comment on function public.random_fish_catches(text, integer) is
    'Generates normal weighted fish catches for an island without duration-based rarity bonuses.';

comment on function public.random_fish_catches_with_rarity_bonus(text, integer, integer) is
    'Generates duration-aware weighted fish catches for an island. One draw may use the rare-or-better pool by policy; if that pool is unavailable, it falls back to the normal weighted draw.';

comment on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) is
    'Creates duration-aware fish catches using session_members.island_id and focus_sessions.duration_seconds for the completing user and target session.';

revoke all on function public.random_fish_catches_with_rarity_bonus(text, integer, integer) from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;

notify pgrst, 'reload schema';
