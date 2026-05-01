update public.sea_critters
set rarity = 'rare',
    drop_weight = case
        when drop_weight = 5 then 25
        else drop_weight
    end
where id = 'tuna'
    and (
        rarity is distinct from 'rare'
        or drop_weight = 5
    );

update public.user_fish_catches
set rarity = 'rare'
where sea_critter_id = 'tuna'
    and rarity is distinct from 'rare';

-- Validation: tuna should remain a valid catalog-backed fish, but no longer
-- belongs to the ultra rare rarity tier.
do $$
declare
    invalid_count integer;
begin
    select count(*)
    into invalid_count
    from public.sea_critters
    where id = 'tuna'
        and rarity = 'rare'
        and sell_value = 3;

    if invalid_count <> 1 then
        raise exception 'Cannot demote tuna: expected one tuna catalog row with rarity rare and sell_value 3.';
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where sea_critter_id = 'tuna'
        and rarity is distinct from 'rare';

    if invalid_count > 0 then
        raise exception 'Cannot demote tuna: % tuna catch rows still have non-rare rarity.', invalid_count;
    end if;
end $$;

notify pgrst, 'reload schema';
