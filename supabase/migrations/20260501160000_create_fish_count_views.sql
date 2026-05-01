create view public.user_fish_collection_counts
with (security_invoker = true)
as
select
    user_fish_catches.user_id,
    user_fish_catches.sea_critter_id,
    sea_critters.display_name,
    sea_critters.rarity,
    sea_critters.sell_value,
    sea_critters.asset_name,
    sea_critters.sort_order,
    count(*)::integer as count
from public.user_fish_catches
join public.sea_critters
    on sea_critters.id = user_fish_catches.sea_critter_id
where user_fish_catches.user_id = auth.uid()
group by
    user_fish_catches.user_id,
    user_fish_catches.sea_critter_id,
    sea_critters.display_name,
    sea_critters.rarity,
    sea_critters.sell_value,
    sea_critters.asset_name,
    sea_critters.sort_order;

create view public.user_fish_inventory_counts
with (security_invoker = true)
as
select
    user_fish_catches.user_id,
    user_fish_catches.sea_critter_id,
    sea_critters.display_name,
    sea_critters.rarity,
    sea_critters.sell_value,
    sea_critters.asset_name,
    sea_critters.sort_order,
    count(*)::integer as count
from public.user_fish_catches
join public.sea_critters
    on sea_critters.id = user_fish_catches.sea_critter_id
where user_fish_catches.user_id = auth.uid()
    and user_fish_catches.sold_at is null
group by
    user_fish_catches.user_id,
    user_fish_catches.sea_critter_id,
    sea_critters.display_name,
    sea_critters.rarity,
    sea_critters.sell_value,
    sea_critters.asset_name,
    sea_critters.sort_order;

revoke all on public.user_fish_collection_counts from public, anon, authenticated;
revoke all on public.user_fish_inventory_counts from public, anon, authenticated;

grant select on public.user_fish_collection_counts to authenticated;
grant select on public.user_fish_inventory_counts to authenticated;

notify pgrst, 'reload schema';
