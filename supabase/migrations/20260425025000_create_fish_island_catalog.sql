create table public.sea_critters (
    id text primary key,
    display_name text not null,
    rarity text not null,
    sell_value bigint not null,
    asset_name text not null,
    sort_order integer not null,
    drop_weight numeric not null,
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint sea_critters_rarity_valid
        check (rarity in ('common', 'rare', 'ultra_rare')),
    constraint sea_critters_sell_value_positive
        check (sell_value > 0),
    constraint sea_critters_drop_weight_nonnegative
        check (drop_weight >= 0),
    constraint sea_critters_display_name_unique
        unique (display_name),
    constraint sea_critters_asset_name_unique
        unique (asset_name),
    constraint sea_critters_sort_order_unique
        unique (sort_order)
);

create trigger set_public_sea_critters_updated_at
before update on public.sea_critters
for each row
execute function public.set_updated_at();

alter table public.sea_critters enable row level security;

create policy "Authenticated users can read enabled sea critters"
on public.sea_critters
for select
to authenticated
using (is_enabled);

revoke all on public.sea_critters from public, anon, authenticated;
grant select on public.sea_critters to authenticated;

create table public.islands (
    id text primary key,
    display_name text not null,
    sort_order integer not null,
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint islands_id_slug_style
        check (id ~ '^[a-z0-9_]+$'),
    constraint islands_display_name_unique
        unique (display_name),
    constraint islands_sort_order_unique
        unique (sort_order)
);

create trigger set_public_islands_updated_at
before update on public.islands
for each row
execute function public.set_updated_at();

alter table public.islands enable row level security;

create policy "Authenticated users can read enabled islands"
on public.islands
for select
to authenticated
using (is_enabled);

revoke all on public.islands from public, anon, authenticated;
grant select on public.islands to authenticated;

create table public.island_sea_critters (
    island_id text not null references public.islands(id) on delete cascade,
    sea_critter_id text not null references public.sea_critters(id),
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (island_id, sea_critter_id)
);

create trigger set_public_island_sea_critters_updated_at
before update on public.island_sea_critters
for each row
execute function public.set_updated_at();

create index island_sea_critters_enabled_island_idx
on public.island_sea_critters (island_id, sea_critter_id)
where is_enabled;

create index island_sea_critters_enabled_sea_critter_idx
on public.island_sea_critters (sea_critter_id, island_id)
where is_enabled;

alter table public.island_sea_critters enable row level security;

create policy "Authenticated users can read enabled island sea critters"
on public.island_sea_critters
for select
to authenticated
using (
    is_enabled
    and exists (
        select 1
        from public.islands
        where islands.id = island_sea_critters.island_id
            and islands.is_enabled
    )
    and exists (
        select 1
        from public.sea_critters
        where sea_critters.id = island_sea_critters.sea_critter_id
            and sea_critters.is_enabled
    )
);

revoke all on public.island_sea_critters from public, anon, authenticated;
grant select on public.island_sea_critters to authenticated;

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

insert into public.islands (id, display_name, sort_order, is_enabled)
values
    ('default', 'Forest Island', 1, true),
    ('sand', 'Tropical Island', 2, true);

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

create function public.validate_enabled_island_sea_critter()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.is_enabled
        and not exists (
            select 1
            from public.islands
            where islands.id = new.island_id
                and islands.is_enabled
        )
    then
        raise exception 'Island fish cannot be enabled for disabled or missing island %.', new.island_id using errcode = '23514';
    end if;

    if new.is_enabled
        and not exists (
            select 1
            from public.sea_critters
            where sea_critters.id = new.sea_critter_id
                and sea_critters.is_enabled
        )
    then
        raise exception 'Island fish % cannot be enabled because its sea critter is disabled or missing.', new.sea_critter_id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger validate_enabled_island_sea_critter
before insert or update of island_id, sea_critter_id, is_enabled
on public.island_sea_critters
for each row
execute function public.validate_enabled_island_sea_critter();

create function public.prevent_disabling_enabled_island_sea_critter()
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
            from public.island_sea_critters
            join public.islands
                on islands.id = island_sea_critters.island_id
                and islands.is_enabled
            where island_sea_critters.sea_critter_id = old.id
                and island_sea_critters.is_enabled
        )
    then
        raise exception 'Sea critter % cannot be disabled while it is enabled for an active island.', old.id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger prevent_disabling_enabled_island_sea_critter
before update of is_enabled
on public.sea_critters
for each row
execute function public.prevent_disabling_enabled_island_sea_critter();

revoke all on function public.validate_enabled_island_sea_critter() from public, anon, authenticated;
revoke all on function public.prevent_disabling_enabled_island_sea_critter() from public, anon, authenticated;

do $$
declare
    default_fish_ids text[] := array[
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
    sand_fish_ids text[] := array[
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
    invalid_island_id text;
begin
    select count(*)
    into invalid_count
    from public.island_sea_critters
    where island_id = 'default'
        and is_enabled;

    if invalid_count <> 9 then
        raise exception 'Forest island must have exactly 9 enabled fish, found %.', invalid_count;
    end if;

    select coalesce(array_agg(sea_critter_id order by sea_critter_id), array[]::text[])
    into actual_fish_ids
    from public.island_sea_critters
    where island_id = 'default'
        and is_enabled;

    if actual_fish_ids <> (
        select array_agg(fish_id order by fish_id)
        from unnest(default_fish_ids) as approved_default(fish_id)
    ) then
        raise exception 'Forest island enabled fish do not match the approved list.';
    end if;

    select count(*)
    into invalid_count
    from public.island_sea_critters
    where island_id = 'sand'
        and is_enabled;

    if invalid_count <> 9 then
        raise exception 'Tropical island must have exactly 9 enabled fish, found %.', invalid_count;
    end if;

    select coalesce(array_agg(sea_critter_id order by sea_critter_id), array[]::text[])
    into actual_fish_ids
    from public.island_sea_critters
    where island_id = 'sand'
        and is_enabled;

    if actual_fish_ids <> (
        select array_agg(fish_id order by fish_id)
        from unnest(sand_fish_ids) as approved_sand(fish_id)
    ) then
        raise exception 'Tropical island enabled fish do not match the approved list.';
    end if;

    select count(*)
    into invalid_count
    from public.sea_critters
    where is_enabled
        and not (id = any(approved_fish_ids));

    if invalid_count > 0 then
        raise exception 'Only approved island fish may be enabled; found % unapproved enabled fish.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.island_sea_critters
    join public.sea_critters
        on sea_critters.id = island_sea_critters.sea_critter_id
    where island_sea_critters.is_enabled
        and not sea_critters.is_enabled;

    if invalid_count > 0 then
        raise exception 'Enabled island availability cannot reference disabled fish; found % rows.', invalid_count;
    end if;

    select islands.id
    into invalid_island_id
    from public.islands
    where islands.is_enabled
        and coalesce((
            select sum(sea_critters.drop_weight)
            from public.island_sea_critters
            join public.sea_critters
                on sea_critters.id = island_sea_critters.sea_critter_id
            where island_sea_critters.island_id = islands.id
                and island_sea_critters.is_enabled
                and sea_critters.is_enabled
                and sea_critters.drop_weight > 0
        ), 0) <= 0
    order by islands.id
    limit 1;

    if invalid_island_id is not null then
        raise exception 'Enabled island % has no positive total fish drop weight.', invalid_island_id;
    end if;
end $$;

notify pgrst, 'reload schema';
