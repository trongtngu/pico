with legacy_critters (
    id,
    display_name,
    rarity,
    sell_value,
    asset_name,
    drop_weight,
    is_enabled,
    fallback_order
) as (
    values
        ('bass', 'Bass', 'common', 1::bigint, 'Fish_Bass', 100::numeric, true, 1),
        ('salmon', 'Salmon', 'rare', 2::bigint, 'Fish_Salmon', 25::numeric, true, 2),
        ('tuna', 'Tuna', 'ultra_rare', 3::bigint, 'Fish_Tuna', 5::numeric, true, 3)
),
next_sort_order as (
    select coalesce(max(sort_order), 0) as value
    from public.sea_critters
)
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
select
    legacy_critters.id,
    legacy_critters.display_name,
    legacy_critters.rarity,
    legacy_critters.sell_value,
    legacy_critters.asset_name,
    next_sort_order.value + row_number() over (order by legacy_critters.fallback_order),
    legacy_critters.drop_weight,
    legacy_critters.is_enabled
from legacy_critters
cross join next_sort_order
where not exists (
    select 1
    from public.sea_critters
    where sea_critters.id = legacy_critters.id
)
on conflict (id) do nothing;

do $$
declare
    missing_legacy_catalog_count integer;
begin
    select count(*)
    into missing_legacy_catalog_count
    from (
        values ('bass'), ('salmon'), ('tuna')
    ) legacy_ids(id)
    left join public.sea_critters critters
        on critters.id = legacy_ids.id
    where critters.id is null;

    if missing_legacy_catalog_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % legacy sea_critters catalog rows are missing.', missing_legacy_catalog_count;
    end if;
end $$;

alter table public.user_fish_catches
drop constraint if exists user_fish_catches_fish_type_valid;

alter table public.user_fish_catches
drop constraint if exists user_fish_catches_fish_value_matches_type;

alter table public.user_fish_catches
drop constraint if exists user_fish_catches_rarity_valid;

update public.user_fish_catches
set sea_critter_id = fish_type
where sea_critter_id is null
    and fish_type in ('bass', 'salmon', 'tuna');

update public.user_fish_catches
set fish_type = sea_critter_id
where sea_critter_id is not null
    and fish_type is distinct from sea_critter_id;

update public.user_fish_catches
set rarity = case sea_critter_id
        when 'bass' then 'common'
        when 'salmon' then 'rare'
        when 'tuna' then 'ultra_rare'
        else rarity
    end,
    sell_value = case sea_critter_id
        when 'bass' then 1
        when 'salmon' then 2
        when 'tuna' then 3
        else sell_value
    end
where sea_critter_id in ('bass', 'salmon', 'tuna')
    and (
        rarity is distinct from case sea_critter_id
            when 'bass' then 'common'
            when 'salmon' then 'rare'
            when 'tuna' then 'ultra_rare'
        end
        or sell_value is distinct from case sea_critter_id
            when 'bass' then 1
            when 'salmon' then 2
            when 'tuna' then 3
        end
    );

update public.user_fish_catches
set rarity = 'rare'
where rarity = 'uncommon'
    and sea_critter_id = 'salmon';

-- Validation: stop the migration if any catch row still cannot satisfy the
-- catalog-backed fish model.
do $$
declare
    invalid_count integer;
begin
    select count(*)
    into invalid_count
    from public.user_fish_catches
    where sea_critter_id is null;

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows have null sea_critter_id.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where rarity = 'uncommon';

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows still use legacy rarity uncommon.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches catches
    left join public.sea_critters critters
        on critters.id = catches.sea_critter_id
    where critters.id is null;

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows reference a sea_critter_id missing from sea_critters.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where fish_type is distinct from sea_critter_id;

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows do not mirror fish_type and sea_critter_id.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where rarity not in ('common', 'rare', 'ultra_rare');

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows have invalid rarity values.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where sell_value <= 0;

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % rows have non-positive sell_value.', invalid_count;
    end if;

    select count(*)
    into invalid_count
    from public.user_fish_catches
    where sea_critter_id in ('bass', 'salmon', 'tuna')
        and not (
            (sea_critter_id = 'bass' and rarity = 'common' and sell_value = 1)
            or (sea_critter_id = 'salmon' and rarity = 'rare' and sell_value = 2)
            or (sea_critter_id = 'tuna' and rarity = 'ultra_rare' and sell_value = 3)
        );

    if invalid_count > 0 then
        raise exception 'Cannot validate user_fish_catches: % legacy bass/salmon/tuna rows still have incorrect rarity or sell_value.', invalid_count;
    end if;
end $$;

alter table public.user_fish_catches
alter column sea_critter_id set not null;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_fish_catches'::regclass
            and conname = 'user_fish_catches_sea_critter_id_fkey'
    ) then
        alter table public.user_fish_catches
        add constraint user_fish_catches_sea_critter_id_fkey
        foreign key (sea_critter_id) references public.sea_critters(id);
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_fish_catches'::regclass
            and conname = 'user_fish_catches_fish_type_matches_sea_critter'
    ) then
        alter table public.user_fish_catches
        add constraint user_fish_catches_fish_type_matches_sea_critter
        check (fish_type = sea_critter_id);
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_fish_catches'::regclass
            and conname = 'user_fish_catches_rarity_valid'
    ) then
        alter table public.user_fish_catches
        add constraint user_fish_catches_rarity_valid
        check (rarity in ('common', 'rare', 'ultra_rare'));
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_fish_catches'::regclass
            and conname = 'user_fish_catches_sell_value_positive'
    ) then
        alter table public.user_fish_catches
        add constraint user_fish_catches_sell_value_positive
        check (sell_value > 0);
    end if;
end $$;

create index if not exists user_fish_catches_user_sea_critter_idx
on public.user_fish_catches (user_id, sea_critter_id);

create index if not exists user_fish_catches_user_unsold_sea_critter_idx
on public.user_fish_catches (user_id, sea_critter_id)
where sold_at is null;

notify pgrst, 'reload schema';
