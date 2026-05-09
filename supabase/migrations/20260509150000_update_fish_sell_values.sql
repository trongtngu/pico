update public.sea_critters
set sell_value = case rarity
    when 'rare' then 3
    when 'ultra_rare' then 8
    else sell_value
end
where rarity in ('rare', 'ultra_rare');

update public.user_fish_catches
set sell_value = case rarity
    when 'rare' then 3
    when 'ultra_rare' then 8
    else sell_value
end
where rarity in ('rare', 'ultra_rare')
    and sold_at is null;
