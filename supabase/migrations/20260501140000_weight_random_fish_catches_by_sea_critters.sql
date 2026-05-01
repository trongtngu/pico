alter table public.user_fish_catches
drop constraint user_fish_catches_fish_value_matches_type;

alter table public.user_fish_catches
drop constraint user_fish_catches_fish_type_valid;

alter table public.user_fish_catches
add constraint user_fish_catches_fish_type_matches_sea_critter
check (fish_type = sea_critter_id);

alter table public.user_fish_catches
add constraint user_fish_catches_sell_value_positive
check (sell_value > 0);

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
    draw_weight numeric;
    total_weight numeric;
    selected_critter record;
begin
    select coalesce(sum(sea_critters.drop_weight), 0)
    into total_weight
    from public.sea_critters
    where sea_critters.is_enabled
        and sea_critters.drop_weight > 0;

    if total_weight <= 0 then
        raise exception 'No enabled sea critters with positive drop weight are available.' using errcode = 'P0002';
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
            from public.sea_critters
            where sea_critters.is_enabled
                and sea_critters.drop_weight > 0
        ) weighted_critters
        where weighted_critters.cumulative_weight > draw_weight
        order by weighted_critters.cumulative_weight
        limit 1;

        catch_index := draw_index;
        fish_type := selected_critter.id;
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
begin
    insert into public.user_fish_catches (
        user_id,
        session_id,
        catch_index,
        fish_type,
        sea_critter_id,
        rarity,
        sell_value,
        caught_at
    )
    select
        completing_user_id,
        target_session_id,
        random_fish_catches.catch_index,
        random_fish_catches.fish_type,
        random_fish_catches.fish_type,
        random_fish_catches.rarity,
        random_fish_catches.sell_value,
        catch_time
    from public.random_fish_catches()
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

revoke all on function public.random_fish_catches() from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;

notify pgrst, 'reload schema';
