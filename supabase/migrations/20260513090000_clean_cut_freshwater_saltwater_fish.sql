delete from public.user_fish_catches;
delete from public.island_sea_critters;
delete from public.sea_critters;

insert into public.sea_critters (
    id,
    display_name,
    rarity,
    sell_value,
    asset_name,
    sort_order,
    drop_weight,
    is_enabled
)
values
    ('carp', 'Carp', 'common', 1, 'freshwater/common_carp', 1, 100, true),
    ('crucian', 'Crucian', 'common', 1, 'freshwater/common_crucian', 2, 100, true),
    ('pale_chub', 'Pale Chub', 'common', 1, 'freshwater/common_pale_chub', 3, 100, true),
    ('shad', 'Shad', 'common', 1, 'freshwater/common_shad', 4, 100, true),
    ('angelfish', 'Angelfish', 'rare', 3, 'freshwater/rare_angelfish', 5, 25, true),
    ('leopoldi', 'Leopoldi', 'rare', 3, 'freshwater/rare_leopoldi', 6, 25, true),
    ('sturgeon', 'Sturgeon', 'rare', 3, 'freshwater/rare_sturgeon', 7, 25, true),
    ('arowana', 'Arowana', 'ultra_rare', 8, 'freshwater/super_rare_arowana', 8, 5, true),
    ('pirarucu', 'Pirarucu', 'ultra_rare', 8, 'freshwater/super_rare_pirarucu', 9, 5, true),
    ('anchovy', 'Anchovy', 'common', 1, 'saltwater/common_anchovy', 10, 100, true),
    ('mackerel', 'Mackerel', 'common', 1, 'saltwater/common_mackerel', 11, 100, true),
    ('sea_bass', 'Sea Bass', 'common', 1, 'saltwater/common_sea_bass', 12, 100, true),
    ('trevally', 'Trevally', 'common', 1, 'saltwater/common_trevally', 13, 100, true),
    ('blue_tang', 'Blue Tang', 'rare', 3, 'saltwater/rare_blue_tang', 14, 25, true),
    ('clownfish', 'Clownfish', 'rare', 3, 'saltwater/rare_clownfish', 15, 25, true),
    ('pomfret', 'Pomfret', 'rare', 3, 'saltwater/rare_pomfret', 16, 25, true),
    ('great_white', 'Great White', 'ultra_rare', 8, 'saltwater/super_rare_great_white', 17, 5, true),
    ('whale_shark', 'Whale Shark', 'ultra_rare', 8, 'saltwater/super_rare_whale_shark', 18, 5, true);

insert into public.island_sea_critters (island_id, sea_critter_id, is_enabled)
values
    ('default', 'carp', true),
    ('default', 'crucian', true),
    ('default', 'pale_chub', true),
    ('default', 'shad', true),
    ('default', 'angelfish', true),
    ('default', 'leopoldi', true),
    ('default', 'sturgeon', true),
    ('default', 'arowana', true),
    ('default', 'pirarucu', true),
    ('sand', 'anchovy', true),
    ('sand', 'mackerel', true),
    ('sand', 'sea_bass', true),
    ('sand', 'trevally', true),
    ('sand', 'blue_tang', true),
    ('sand', 'clownfish', true),
    ('sand', 'pomfret', true),
    ('sand', 'great_white', true),
    ('sand', 'whale_shark', true);

do $$
declare
    freshwater_fish_ids text[] := array[
        'carp',
        'crucian',
        'pale_chub',
        'shad',
        'angelfish',
        'leopoldi',
        'sturgeon',
        'arowana',
        'pirarucu'
    ];
    saltwater_fish_ids text[] := array[
        'anchovy',
        'mackerel',
        'sea_bass',
        'trevally',
        'blue_tang',
        'clownfish',
        'pomfret',
        'great_white',
        'whale_shark'
    ];
    approved_fish_ids text[] := array[
        'carp',
        'crucian',
        'pale_chub',
        'shad',
        'angelfish',
        'leopoldi',
        'sturgeon',
        'arowana',
        'pirarucu',
        'anchovy',
        'mackerel',
        'sea_bass',
        'trevally',
        'blue_tang',
        'clownfish',
        'pomfret',
        'great_white',
        'whale_shark'
    ];
    actual_fish_ids text[];
    invalid_count integer;
begin
    select coalesce(array_agg(sea_critter_id order by sea_critter_id), array[]::text[])
    into actual_fish_ids
    from public.island_sea_critters
    where island_id = 'default'
        and is_enabled;

    if actual_fish_ids <> (
        select array_agg(fish_id order by fish_id)
        from unnest(freshwater_fish_ids) as approved_default(fish_id)
    ) then
        raise exception 'Forest island enabled fish do not match the approved freshwater list.';
    end if;

    select coalesce(array_agg(sea_critter_id order by sea_critter_id), array[]::text[])
    into actual_fish_ids
    from public.island_sea_critters
    where island_id = 'sand'
        and is_enabled;

    if actual_fish_ids <> (
        select array_agg(fish_id order by fish_id)
        from unnest(saltwater_fish_ids) as approved_sand(fish_id)
    ) then
        raise exception 'Tropical island enabled fish do not match the approved saltwater list.';
    end if;

    select count(*)
    into invalid_count
    from public.sea_critters
    where is_enabled
        and not (id = any(approved_fish_ids));

    if invalid_count > 0 then
        raise exception 'Only approved freshwater and saltwater fish may be enabled; found % unapproved enabled fish.', invalid_count;
    end if;
end $$;

notify pgrst, 'reload schema';
