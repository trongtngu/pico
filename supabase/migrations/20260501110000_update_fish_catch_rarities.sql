alter table public.user_fish_catches
drop constraint user_fish_catches_fish_value_matches_type;

alter table public.user_fish_catches
drop constraint user_fish_catches_rarity_valid;

update public.user_fish_catches
set rarity = 'ultra_rare'
where fish_type = 'tuna'
    and rarity = 'rare';

update public.user_fish_catches
set rarity = 'rare'
where fish_type = 'salmon'
    and rarity = 'uncommon';

alter table public.user_fish_catches
add constraint user_fish_catches_rarity_valid
check (rarity in ('common', 'rare', 'ultra_rare'));

alter table public.user_fish_catches
add constraint user_fish_catches_fish_value_matches_type
check (
    (fish_type = 'bass' and rarity = 'common' and sell_value = 1)
    or (fish_type = 'salmon' and rarity = 'rare' and sell_value = 2)
    or (fish_type = 'tuna' and rarity = 'ultra_rare' and sell_value = 3)
);

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
            rarity := 'ultra_rare';
            sell_value := 3;
        elsif roll < 0.20 then
            fish_type := 'salmon';
            rarity := 'rare';
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

revoke all on function public.random_fish_catches() from public, anon, authenticated;

notify pgrst, 'reload schema';
