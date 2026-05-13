create schema if not exists private;
create extension if not exists pgcrypto;

revoke create on schema public from public;
revoke execute on all functions in schema public from public;
alter default privileges in schema public revoke execute on functions from public;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace function public.validate_avatar_config(config jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
    select case
        when config is null or jsonb_typeof(config) <> 'object' then false
        when
            config ->> 'version' = '1'
            and config ->> 'character' = 'character_0'
            and jsonb_typeof(config -> 'hat') = 'number'
            and config ->> 'hat' ~ '^[0-5]$'
            and (select count(*) from jsonb_object_keys(config)) = 3
        then true
        else
            config ->> 'type' = 'preset'
            and config ->> 'key' in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4')
            and (select count(*) from jsonb_object_keys(config)) = 2
    end;
$$;

create table public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    username text not null unique,
    display_name text not null,
    avatar_config jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_profiles_username_format
        check (username ~ '^[a-z0-9_]{3,24}$'),
    constraint user_profiles_display_name_format
        check (
            display_name = btrim(display_name)
            and char_length(display_name) between 1 and 40
        ),
    constraint user_profiles_avatar_config_format
        check (public.validate_avatar_config(avatar_config))
);

create table private.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    user_timezone text not null default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint private_user_profiles_user_timezone_not_blank
        check (length(btrim(user_timezone)) > 0)
);

create trigger set_public_users_updated_at
before update on public.users
for each row execute function public.set_updated_at();

create trigger set_public_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

create trigger set_private_user_profiles_updated_at
before update on private.user_profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
security definer
set search_path = public, private
language plpgsql
as $$
declare
    fallback_username text := 'pico_' || substring(replace(new.id::text, '-', '') from 1 for 19);
    email_prefix text := split_part(coalesce(new.email, ''), '@', 1);
    profile_username text := coalesce(
        nullif(lower(btrim(new.raw_user_meta_data ->> 'username')), ''),
        fallback_username
    );
    profile_display_name text := coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
        nullif(btrim(email_prefix), ''),
        'Pico'
    );
    profile_avatar_config jsonb := coalesce(
        new.raw_user_meta_data -> 'avatar_config',
        jsonb_build_object('version', 1, 'character', 'character_0', 'hat', 0)
    );
    profile_timezone text := coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'time_zone'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'timezone'), ''),
        'UTC'
    );
begin
    profile_display_name := left(profile_display_name, 40);

    if profile_username !~ '^[a-z0-9_]{3,24}$' then
        profile_username := fallback_username;
    end if;

    if profile_display_name is null or char_length(profile_display_name) not between 1 and 40 then
        profile_display_name := 'Pico';
    end if;

    if profile_avatar_config is null or not public.validate_avatar_config(profile_avatar_config) then
        profile_avatar_config := jsonb_build_object('version', 1, 'character', 'character_0', 'hat', 0);
    end if;

    if not exists (
        select 1
        from pg_timezone_names
        where name = profile_timezone
    ) then
        profile_timezone := 'UTC';
    end if;

    insert into public.users (id)
    values (new.id)
    on conflict (id) do nothing;

    insert into public.user_profiles (user_id, username, display_name, avatar_config)
    values (new.id, profile_username, profile_display_name, profile_avatar_config)
    on conflict (user_id) do nothing;

    insert into private.user_profiles (user_id, user_timezone)
    values (new.id, profile_timezone)
    on conflict (user_id) do nothing;

    return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

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
    constraint sea_critters_display_name_unique unique (display_name),
    constraint sea_critters_asset_name_unique unique (asset_name),
    constraint sea_critters_sort_order_unique unique (sort_order)
);

create table public.islands (
    id text primary key,
    display_name text not null,
    sort_order integer not null,
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint islands_id_slug_style
        check (id ~ '^[a-z0-9_]+$'),
    constraint islands_display_name_unique unique (display_name),
    constraint islands_sort_order_unique unique (sort_order)
);

create table public.island_sea_critters (
    island_id text not null references public.islands(id) on delete cascade,
    sea_critter_id text not null references public.sea_critters(id),
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (island_id, sea_critter_id)
);

create trigger set_public_sea_critters_updated_at
before update on public.sea_critters
for each row execute function public.set_updated_at();

create trigger set_public_islands_updated_at
before update on public.islands
for each row execute function public.set_updated_at();

create trigger set_public_island_sea_critters_updated_at
before update on public.island_sea_critters
for each row execute function public.set_updated_at();

create index island_sea_critters_enabled_island_idx
on public.island_sea_critters (island_id, sea_critter_id)
where is_enabled;

create index island_sea_critters_enabled_sea_critter_idx
on public.island_sea_critters (sea_critter_id, island_id)
where is_enabled;

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
for each row execute function public.validate_enabled_island_sea_critter();

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
before update of is_enabled on public.sea_critters
for each row execute function public.prevent_disabling_enabled_island_sea_critter();

insert into public.sea_critters (
    id, display_name, rarity, sell_value, asset_name, sort_order, drop_weight, is_enabled
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

create table public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null references public.user_profiles(user_id) on delete cascade,
    recipient_id uuid not null references public.user_profiles(user_id) on delete cascade,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint friend_requests_different_users
        check (requester_id <> recipient_id),
    constraint friend_requests_status
        check (status in ('pending', 'accepted', 'rejected'))
);

create unique index friend_requests_pending_pair_unique
on public.friend_requests (least(requester_id, recipient_id), greatest(requester_id, recipient_id))
where status = 'pending';

create table public.friendships (
    user_one_id uuid not null references public.user_profiles(user_id) on delete cascade,
    user_two_id uuid not null references public.user_profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    constraint friendships_pkey primary key (user_one_id, user_two_id),
    constraint friendships_canonical_order
        check (user_one_id < user_two_id)
);

create trigger set_public_friend_requests_updated_at
before update on public.friend_requests
for each row execute function public.set_updated_at();

create table public.focus_sessions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.user_profiles(user_id) on delete cascade,
    mode text not null default 'solo',
    status text not null default 'lobby',
    duration_seconds integer not null default 1800,
    started_at timestamptz,
    planned_end_at timestamptz,
    ended_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint focus_sessions_mode
        check (mode in ('solo', 'multiplayer')),
    constraint focus_sessions_status
        check (status in ('lobby', 'launched', 'live', 'interrupted', 'completed', 'cancelled')),
    constraint focus_sessions_duration_seconds
        check (duration_seconds between 600 and 86400),
    constraint focus_sessions_lifecycle_timestamps
        check (
            (status = 'lobby' and started_at is null and planned_end_at is null and ended_at is null)
            or (status in ('launched', 'live') and started_at is not null and planned_end_at is not null and ended_at is null)
            or (status in ('completed', 'interrupted') and started_at is not null and planned_end_at is not null and ended_at is not null)
            or (status = 'cancelled' and ended_at is not null)
        )
);

create unique index focus_sessions_one_open_owner
on public.focus_sessions (owner_id)
where status in ('lobby', 'live');

create table public.session_members (
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    island_id text not null default 'default' references public.islands(id),
    role text not null default 'participant',
    status text not null default 'invited',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint session_members_pkey primary key (session_id, user_id),
    constraint session_members_role
        check (role in ('host', 'participant')),
    constraint session_members_status
        check (status in ('invited', 'joined', 'declined', 'left'))
);

create table public.session_events (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    event_type text not null,
    occurred_at timestamptz not null default now(),
    constraint session_events_type
        check (event_type in ('member_joined', 'session_started', 'member_interrupted', 'member_completed'))
);

create unique index session_events_member_completed_once
on public.session_events (session_id, user_id)
where event_type = 'member_completed';

create unique index session_events_member_interrupted_once
on public.session_events (session_id, user_id)
where event_type = 'member_interrupted';

create index session_members_island_id_idx
on public.session_members (island_id);

create trigger set_public_focus_sessions_updated_at
before update on public.focus_sessions
for each row execute function public.set_updated_at();

create trigger set_public_session_members_updated_at
before update on public.session_members
for each row execute function public.set_updated_at();

create function public.reject_session_events_mutation()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    raise exception 'session_events is append-only.' using errcode = '2F000';
end;
$$;

create trigger reject_public_session_events_update
before update on public.session_events
for each row execute function public.reject_session_events_mutation();

create trigger reject_public_session_events_delete
before delete on public.session_events
for each row execute function public.reject_session_events_mutation();

create table public.villages (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.user_profiles(user_id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint villages_owner_unique unique (owner_id)
);

create table public.village_residents (
    village_id uuid not null references public.villages(id) on delete cascade,
    resident_user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    first_completed_session_id uuid not null references public.focus_sessions(id) on delete cascade,
    unlocked_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint village_residents_pkey primary key (village_id, resident_user_id)
);

create table public.villager_bonds (
    user_one_id uuid not null references public.user_profiles(user_id) on delete cascade,
    user_two_id uuid not null references public.user_profiles(user_id) on delete cascade,
    completed_pair_sessions integer not null,
    first_completed_at timestamptz not null,
    last_completed_at timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint villager_bonds_pkey primary key (user_one_id, user_two_id),
    constraint villager_bonds_canonical_order
        check (user_one_id < user_two_id),
    constraint villager_bonds_completed_pair_sessions_positive
        check (completed_pair_sessions > 0)
);

create index village_residents_resident_user_id_idx
on public.village_residents (resident_user_id);

create index villager_bonds_user_two_id_idx
on public.villager_bonds (user_two_id);

create trigger set_public_villages_updated_at
before update on public.villages
for each row execute function public.set_updated_at();

create trigger set_public_village_residents_updated_at
before update on public.village_residents
for each row execute function public.set_updated_at();

create trigger set_public_villager_bonds_updated_at
before update on public.villager_bonds
for each row execute function public.set_updated_at();

create function public.villager_bond_level(completed_pair_sessions integer)
returns integer
language sql
immutable
set search_path = public
as $$
    select case
        when coalesce(completed_pair_sessions, 0) >= 30 then 5
        when coalesce(completed_pair_sessions, 0) >= 14 then 4
        when coalesce(completed_pair_sessions, 0) >= 7 then 3
        when coalesce(completed_pair_sessions, 0) >= 3 then 2
        when coalesce(completed_pair_sessions, 0) >= 1 then 1
        else 0
    end;
$$;

create function public.ensure_user_village()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    insert into public.villages (owner_id)
    values (new.user_id)
    on conflict (owner_id) do nothing;

    return new;
end;
$$;

create trigger on_public_user_profile_created_ensure_village
after insert on public.user_profiles
for each row execute function public.ensure_user_village();

create table public.user_berry_balances (
    user_id uuid primary key references public.user_profiles(user_id) on delete cascade,
    berries bigint not null default 0,
    completion_streak integer not null default 0,
    last_completed_on date,
    last_completed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_berry_balances_berries_nonnegative
        check (berries >= 0),
    constraint user_berry_balances_completion_streak_nonnegative
        check (completion_streak >= 0),
    constraint user_berry_balances_streak_requires_completion_day
        check (
            (completion_streak = 0 and last_completed_on is null and last_completed_at is null)
            or (completion_streak > 0 and last_completed_on is not null and last_completed_at is not null)
        )
);

create trigger set_public_user_berry_balances_updated_at
before update on public.user_berry_balances
for each row execute function public.set_updated_at();

create table public.store_items (
    id text primary key,
    item_type text not null,
    item_key text not null,
    display_name text not null,
    berry_price bigint not null,
    is_enabled boolean not null default true,
    is_limited boolean not null default false,
    is_paid_only boolean not null default false,
    sort_order integer not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint store_items_type_valid
        check (item_type in ('hat', 'island')),
    constraint store_items_price_nonnegative
        check (berry_price >= 0),
    constraint store_items_metadata_object
        check (jsonb_typeof(metadata) = 'object'),
    constraint store_items_type_key_unique
        unique (item_type, item_key)
);

create table public.user_store_inventory (
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    store_item_id text not null references public.store_items(id),
    acquired_at timestamptz not null default now(),
    acquisition_source text not null default 'berries',
    primary key (user_id, store_item_id)
);

create index user_store_inventory_item_idx
on public.user_store_inventory (store_item_id, user_id);

create trigger set_public_store_items_updated_at
before update on public.store_items
for each row execute function public.set_updated_at();

insert into public.store_items (
    id, item_type, item_key, display_name, berry_price, is_enabled, is_limited, is_paid_only, sort_order, metadata
)
values
    ('island:sand', 'island', 'sand', 'Beach Island', 2000, true, false, false, 10, '{"island_id": "sand"}'::jsonb),
    ('hat:1', 'hat', '1', 'Bamboo Hat', 15, true, false, false, 101, '{"hat": 1}'::jsonb),
    ('hat:2', 'hat', '2', 'Beanie', 150, true, false, false, 102, '{"hat": 2}'::jsonb),
    ('hat:3', 'hat', '3', 'Bow', 150, true, false, false, 103, '{"hat": 3}'::jsonb),
    ('hat:4', 'hat', '4', 'Helmet', 150, true, false, false, 104, '{"hat": 4}'::jsonb),
    ('hat:5', 'hat', '5', 'Shark Hat', 1000, true, false, false, 105, '{"hat": 5}'::jsonb);

create table public.user_fish_catches (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    catch_index integer not null,
    sea_critter_id text not null references public.sea_critters(id),
    rarity text not null,
    sell_value bigint not null,
    caught_at timestamptz not null default now(),
    sold_at timestamptz,
    sold_for_berries bigint,
    constraint user_fish_catches_catch_index_valid
        check (catch_index between 1 and 12),
    constraint user_fish_catches_user_session_catch_unique
        unique (user_id, session_id, catch_index),
    constraint user_fish_catches_rarity_valid
        check (rarity in ('common', 'rare', 'ultra_rare')),
    constraint user_fish_catches_sell_value_positive
        check (sell_value > 0),
    constraint user_fish_catches_sold_state_valid
        check (
            (sold_at is null and sold_for_berries is null)
            or (sold_at is not null and sold_for_berries is not null)
        ),
    constraint user_fish_catches_sold_for_berries_positive
        check (sold_for_berries is null or sold_for_berries > 0)
);

create index user_fish_catches_user_caught_at_idx
on public.user_fish_catches (user_id, caught_at desc);

create index user_fish_catches_user_unsold_idx
on public.user_fish_catches (user_id, caught_at desc)
where sold_at is null;

create index user_fish_catches_session_user_idx
on public.user_fish_catches (session_id, user_id);

create function public.validate_session_member_island()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if not exists (
        select 1
        from public.islands
        where islands.id = new.island_id
            and islands.is_enabled
    ) then
        raise exception 'Session member island % is not enabled or does not exist.', new.island_id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger validate_session_member_island
before insert or update of island_id
on public.session_members
for each row execute function public.validate_session_member_island();

create function public.prevent_disabling_session_member_island()
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
            from public.session_members
            where session_members.island_id = old.id
        )
    then
        raise exception 'Island % cannot be disabled while session members reference it.', old.id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger prevent_disabling_session_member_island
before update of is_enabled on public.islands
for each row execute function public.prevent_disabling_session_member_island();

create function public.validate_daily_village_snapshot_owner_profile(owner_id uuid, profile jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
    select case
        when owner_id is null then false
        when profile is null or jsonb_typeof(profile) <> 'object' then false
        when (profile ->> 'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
        else coalesce(
            (profile ->> 'user_id')::uuid = owner_id
            and profile ->> 'username' ~ '^[a-z0-9_]{3,24}$'
            and profile ->> 'display_name' = btrim(profile ->> 'display_name')
            and char_length(profile ->> 'display_name') between 1 and 40
            and public.validate_avatar_config(profile -> 'avatar_config')
            and (select count(*) from jsonb_object_keys(profile)) = 4,
            false
        )
    end;
$$;

create function public.validate_daily_village_snapshot_visitors(owner_id uuid, visitors jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
    select case
        when owner_id is null then false
        when visitors is null or jsonb_typeof(visitors) <> 'array' then false
        else
            not exists (
                select 1
                from jsonb_array_elements(visitors) as visitor_entries(visitor)
                where not case
                    when jsonb_typeof(visitor) <> 'object' then false
                    when not (
                        visitor ? 'user_id'
                        and visitor ? 'username'
                        and visitor ? 'display_name'
                        and visitor ? 'avatar_config'
                        and visitor ? 'bond_level'
                        and visitor ? 'completed_pair_sessions'
                    ) then false
                    when coalesce((visitor ->> 'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', true) then false
                    when lower(visitor ->> 'user_id') = lower(owner_id::text) then false
                    when coalesce(visitor ->> 'username' !~ '^[a-z0-9_]{3,24}$', true) then false
                    when coalesce(visitor ->> 'display_name' <> btrim(visitor ->> 'display_name'), true) then false
                    when coalesce(char_length(visitor ->> 'display_name') not between 1 and 40, true) then false
                    when not public.validate_avatar_config(visitor -> 'avatar_config') then false
                    when coalesce((visitor ->> 'bond_level') !~ '^[0-9]+$', true) then false
                    when coalesce((visitor ->> 'completed_pair_sessions') !~ '^[0-9]+$', true) then false
                    else coalesce(
                        (visitor ->> 'bond_level')::integer between 0 and 5
                        and (visitor ->> 'completed_pair_sessions')::integer >= 0
                        and (select count(*) from jsonb_object_keys(visitor)) = 6,
                        false
                    )
                end
            )
            and (
                select count(*) = count(distinct lower(visitor ->> 'user_id'))
                from jsonb_array_elements(visitors) as visitor_entries(visitor)
            )
    end;
$$;

create function public.validate_daily_village_snapshot_focus_session_ids(focus_session_ids uuid[])
returns boolean
language sql
immutable
set search_path = public
as $$
    select case
        when focus_session_ids is null then false
        else
            not exists (
                select 1
                from unnest(focus_session_ids) as session_ids(session_id)
                where session_id is null
            )
            and cardinality(focus_session_ids) = (
                select count(distinct session_id)::integer
                from unnest(focus_session_ids) as session_ids(session_id)
            )
    end;
$$;

create function public.merge_daily_village_snapshot_focus_session_ids(existing_ids uuid[], incoming_ids uuid[])
returns uuid[]
language sql
immutable
set search_path = public
as $$
    select coalesce(array_agg(distinct session_id order by session_id), '{}'::uuid[])
    from unnest(coalesce(existing_ids, '{}'::uuid[]) || coalesce(incoming_ids, '{}'::uuid[])) as session_ids(session_id)
    where session_id is not null;
$$;

create function public.merge_daily_village_snapshot_visitors(existing_visitors jsonb, incoming_visitors jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
    with combined_visitors as (
        select visitor, false as is_incoming, ordinal_position
        from jsonb_array_elements(coalesce(existing_visitors, '[]'::jsonb))
            with ordinality as visitor_entries(visitor, ordinal_position)
        union all
        select visitor, true as is_incoming, ordinal_position
        from jsonb_array_elements(coalesce(incoming_visitors, '[]'::jsonb))
            with ordinality as visitor_entries(visitor, ordinal_position)
    ),
    ranked_visitors as (
        select
            visitor,
            row_number() over (
                partition by lower(visitor ->> 'user_id')
                order by is_incoming desc, ordinal_position
            ) as visitor_rank
        from combined_visitors
    )
    select coalesce(
        jsonb_agg(
            visitor
            order by lower(visitor ->> 'display_name'), lower(visitor ->> 'username'), lower(visitor ->> 'user_id')
        ) filter (where visitor_rank = 1),
        '[]'::jsonb
    )
    from ranked_visitors;
$$;

create table public.daily_village_snapshots (
    owner_id uuid not null references public.user_profiles(user_id) on delete cascade,
    snapshot_day date not null,
    user_timezone text not null,
    island_id text not null references public.islands(id),
    owner_profile jsonb not null,
    visitors jsonb not null default '[]'::jsonb,
    focus_session_ids uuid[] not null default '{}'::uuid[],
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint daily_village_snapshots_pkey primary key (owner_id, snapshot_day),
    constraint daily_village_snapshots_user_timezone_not_blank
        check (length(btrim(user_timezone)) > 0),
    constraint daily_village_snapshots_owner_profile_shape
        check (public.validate_daily_village_snapshot_owner_profile(owner_id, owner_profile)),
    constraint daily_village_snapshots_visitors_shape
        check (public.validate_daily_village_snapshot_visitors(owner_id, visitors)),
    constraint daily_village_snapshots_focus_session_ids_shape
        check (public.validate_daily_village_snapshot_focus_session_ids(focus_session_ids)),
    constraint daily_village_snapshots_updated_at_after_created_at
        check (updated_at >= created_at)
);

create index daily_village_snapshots_owner_day_desc_idx
on public.daily_village_snapshots (owner_id, snapshot_day desc);

create trigger set_public_daily_village_snapshots_updated_at
before update on public.daily_village_snapshots
for each row execute function public.set_updated_at();

create function public.validate_daily_village_snapshot_references()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.user_timezone is null
        or length(btrim(new.user_timezone)) = 0
        or not exists (
            select 1
            from pg_timezone_names
            where name = new.user_timezone
        )
    then
        raise exception 'Daily village snapshot timezone % is invalid.', new.user_timezone using errcode = '23514';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = new.island_id
            and islands.is_enabled
    ) then
        raise exception 'Daily village snapshot island % is not enabled or does not exist.', new.island_id using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger validate_daily_village_snapshot_references
before insert or update of user_timezone, island_id
on public.daily_village_snapshots
for each row execute function public.validate_daily_village_snapshot_references();

create function public.prevent_daily_village_snapshot_identity_update()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.owner_id is distinct from old.owner_id
        or new.snapshot_day is distinct from old.snapshot_day
        or new.user_timezone is distinct from old.user_timezone
        or new.island_id is distinct from old.island_id
        or new.owner_profile is distinct from old.owner_profile
        or new.created_at is distinct from old.created_at
    then
        raise exception 'Daily village snapshot identity fields are immutable.' using errcode = '2F000';
    end if;

    return new;
end;
$$;

create trigger prevent_daily_village_snapshot_identity_update
before update on public.daily_village_snapshots
for each row execute function public.prevent_daily_village_snapshot_identity_update();

create function public.user_owns_store_item(target_user_id uuid, target_item_type text, target_item_key text)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select exists (
        select 1
        from public.user_store_inventory
        join public.store_items
            on store_items.id = user_store_inventory.store_item_id
        where user_store_inventory.user_id = target_user_id
            and store_items.item_type = target_item_type
            and store_items.item_key = target_item_key
            and store_items.is_enabled
    );
$$;

create function public.user_owns_avatar_hat(profile_user_id uuid, selected_hat integer)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select
        selected_hat = 0
        or public.user_owns_store_item(profile_user_id, 'hat', selected_hat::text);
$$;

create function public.user_owns_island(target_user_id uuid, island_id text)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select
        coalesce(nullif(lower(btrim(island_id)), ''), 'default') = 'default'
        or public.user_owns_store_item(
            target_user_id,
            'island',
            coalesce(nullif(lower(btrim(island_id)), ''), 'default')
        );
$$;

create function public.enforce_avatar_hat_ownership()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
    selected_hat integer;
begin
    if new.avatar_config is null or jsonb_typeof(new.avatar_config) <> 'object' then
        return new;
    end if;

    if not (new.avatar_config ? 'hat') then
        return new;
    end if;

    if jsonb_typeof(new.avatar_config -> 'hat') is distinct from 'number'
        or new.avatar_config ->> 'hat' !~ '^[0-5]$' then
        return new;
    end if;

    selected_hat := (new.avatar_config ->> 'hat')::integer;

    if not public.user_owns_avatar_hat(new.user_id, selected_hat) then
        raise exception 'You do not own that hat.' using errcode = '42501';
    end if;

    return new;
end;
$$;

create trigger enforce_public_user_profiles_avatar_hat_ownership
before insert or update of avatar_config on public.user_profiles
for each row execute function public.enforce_avatar_hat_ownership();

create function public.is_focus_session_member(target_session_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select exists (
        select 1
        from public.session_members
        where session_members.session_id = target_session_id
            and session_members.user_id = auth.uid()
            and session_members.status in ('joined', 'left')
    );
$$;

create function public.can_read_focus_session_member(target_session_id uuid, target_user_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select public.is_focus_session_member(target_session_id)
        or target_user_id = auth.uid();
$$;

create function public.focus_session_payload(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language sql
stable
as $$
    select jsonb_build_object(
        'id', focus_sessions.id,
        'owner_id', focus_sessions.owner_id,
        'mode', focus_sessions.mode,
        'status', focus_sessions.status,
        'duration_seconds', focus_sessions.duration_seconds,
        'started_at', focus_sessions.started_at,
        'planned_end_at', focus_sessions.planned_end_at,
        'ended_at', focus_sessions.ended_at
    )
    from public.focus_sessions
    where focus_sessions.id = target_session_id;
$$;

create function public.focus_session_detail_payload(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language sql
stable
as $$
    select jsonb_build_object(
        'session', public.focus_session_payload(focus_sessions.id),
        'host', jsonb_build_object(
            'user_id', host_profiles.user_id,
            'username', host_profiles.username,
            'display_name', host_profiles.display_name,
            'avatar_config', host_profiles.avatar_config
        ),
        'members', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'user_id', user_profiles.user_id,
                    'role', session_members.role,
                    'status', session_members.status,
                    'username', user_profiles.username,
                    'display_name', user_profiles.display_name,
                    'avatar_config', user_profiles.avatar_config,
                    'is_completed', exists (
                        select 1
                        from public.session_events
                        where session_events.session_id = session_members.session_id
                            and session_events.user_id = session_members.user_id
                            and session_events.event_type = 'member_completed'
                    ),
                    'is_interrupted', exists (
                        select 1
                        from public.session_events
                        where session_events.session_id = session_members.session_id
                            and session_events.user_id = session_members.user_id
                            and session_events.event_type = 'member_interrupted'
                    )
                )
                order by
                    case session_members.role when 'host' then 0 else 1 end,
                    user_profiles.display_name,
                    user_profiles.username
            )
            from public.session_members
            join public.user_profiles
                on user_profiles.user_id = session_members.user_id
            where session_members.session_id = focus_sessions.id
                and (
                    focus_sessions.status = 'lobby'
                    or session_members.status in ('joined', 'left')
                )
        ), '[]'::jsonb)
    )
    from public.focus_sessions
    join public.user_profiles as host_profiles
        on host_profiles.user_id = focus_sessions.owner_id
    where focus_sessions.id = target_session_id;
$$;

create function public.send_friend_request(recipient_username text)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    recipient uuid;
    request_id uuid;
    user_one uuid;
    user_two uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to send friend requests.' using errcode = '28000';
    end if;

    select user_id
    into recipient
    from public.user_profiles
    where username = lower(btrim(recipient_username))
    limit 1;

    if recipient is null then
        raise exception 'No user found for that username.' using errcode = 'P0002';
    end if;

    if requester = recipient then
        raise exception 'You cannot add yourself as a friend.' using errcode = '22023';
    end if;

    user_one := least(requester, recipient);
    user_two := greatest(requester, recipient);

    if exists (
        select 1
        from public.friendships
        where user_one_id = user_one
            and user_two_id = user_two
    ) then
        raise exception 'You are already friends.' using errcode = '23505';
    end if;

    if exists (
        select 1
        from public.friend_requests
        where status = 'pending'
            and least(requester_id, recipient_id) = user_one
            and greatest(requester_id, recipient_id) = user_two
    ) then
        raise exception 'A friend request is already pending.' using errcode = '23505';
    end if;

    insert into public.friend_requests (requester_id, recipient_id)
    values (requester, recipient)
    returning id into request_id;

    return jsonb_build_object('id', request_id);
end;
$$;

create function public.accept_friend_request(request_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    recipient uuid := auth.uid();
    request_record public.friend_requests%rowtype;
    user_one uuid;
    user_two uuid;
begin
    if recipient is null then
        raise exception 'You must be signed in to accept friend requests.' using errcode = '28000';
    end if;

    select *
    into request_record
    from public.friend_requests
    where id = request_id
        and recipient_id = recipient
        and status = 'pending'
    for update;

    if not found then
        raise exception 'No pending friend request was found.' using errcode = 'P0002';
    end if;

    update public.friend_requests
    set status = 'accepted'
    where id = request_id;

    user_one := least(request_record.requester_id, request_record.recipient_id);
    user_two := greatest(request_record.requester_id, request_record.recipient_id);

    insert into public.friendships (user_one_id, user_two_id)
    values (user_one, user_two)
    on conflict do nothing;

    return jsonb_build_object('id', request_id);
end;
$$;

create function public.reject_friend_request(request_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    recipient uuid := auth.uid();
begin
    if recipient is null then
        raise exception 'You must be signed in to reject friend requests.' using errcode = '28000';
    end if;

    update public.friend_requests
    set status = 'rejected'
    where id = request_id
        and recipient_id = recipient
        and status = 'pending';

    if not found then
        raise exception 'No pending friend request was found.' using errcode = 'P0002';
    end if;

    return jsonb_build_object('id', request_id);
end;
$$;

create function public.list_incoming_friend_requests()
returns table (
    id uuid,
    requester_id uuid,
    username text,
    display_name text,
    avatar_config jsonb,
    created_at timestamptz
)
security definer
set search_path = public
language sql
stable
as $$
    select
        friend_requests.id,
        user_profiles.user_id as requester_id,
        user_profiles.username,
        user_profiles.display_name,
        user_profiles.avatar_config,
        friend_requests.created_at
    from public.friend_requests
    join public.user_profiles
        on user_profiles.user_id = friend_requests.requester_id
    where friend_requests.recipient_id = auth.uid()
        and friend_requests.status = 'pending'
    order by friend_requests.created_at desc;
$$;

create function public.list_friends()
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_config jsonb
)
security definer
set search_path = public
language sql
stable
as $$
    select
        user_profiles.user_id,
        user_profiles.username,
        user_profiles.display_name,
        user_profiles.avatar_config
    from public.friendships
    join public.user_profiles
        on user_profiles.user_id = case
            when friendships.user_one_id = auth.uid() then friendships.user_two_id
            else friendships.user_one_id
        end
    where friendships.user_one_id = auth.uid()
        or friendships.user_two_id = auth.uid()
    order by user_profiles.display_name, user_profiles.username;
$$;

create function public.set_user_timezone(time_zone text)
returns text
security definer
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_time_zone text := nullif(btrim(time_zone), '');
begin
    if requester is null then
        raise exception 'You must be signed in to update your timezone.' using errcode = '28000';
    end if;

    if normalized_time_zone is null or not exists (
        select 1
        from pg_timezone_names
        where name = normalized_time_zone
    ) then
        raise exception 'Invalid timezone.' using errcode = '22023';
    end if;

    insert into private.user_profiles (user_id, user_timezone)
    values (requester, normalized_time_zone)
    on conflict (user_id) do update
    set user_timezone = excluded.user_timezone;

    return normalized_time_zone;
end;
$$;

create function public.record_user_completion_streak(completing_user_id uuid, completed_at timestamptz)
returns void
security definer
set search_path = public, private
language plpgsql
as $$
declare
    completion_timezone text;
    completion_day date;
begin
    select private.user_profiles.user_timezone
    into completion_timezone
    from private.user_profiles
    where private.user_profiles.user_id = completing_user_id;

    if completion_timezone is null or not exists (
        select 1
        from pg_timezone_names
        where name = completion_timezone
    ) then
        completion_timezone := 'UTC';
    end if;

    completion_day := (completed_at at time zone completion_timezone)::date;

    insert into public.user_berry_balances (
        user_id,
        berries,
        completion_streak,
        last_completed_on,
        last_completed_at
    )
    values (
        completing_user_id,
        0,
        1,
        completion_day,
        completed_at
    )
    on conflict (user_id) do update
    set completion_streak = case
            when public.user_berry_balances.last_completed_on is null then 1
            when completion_day < public.user_berry_balances.last_completed_on then public.user_berry_balances.completion_streak
            when completion_day = public.user_berry_balances.last_completed_on then public.user_berry_balances.completion_streak
            when completion_day = public.user_berry_balances.last_completed_on + 1 then public.user_berry_balances.completion_streak + 1
            else 1
        end,
        last_completed_on = case
            when public.user_berry_balances.last_completed_on is null then excluded.last_completed_on
            else greatest(public.user_berry_balances.last_completed_on, excluded.last_completed_on)
        end,
        last_completed_at = case
            when public.user_berry_balances.last_completed_at is null then excluded.last_completed_at
            else greatest(public.user_berry_balances.last_completed_at, excluded.last_completed_at)
        end;
end;
$$;

create function public.fetch_user_berries()
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz
)
security definer
set search_path = public
language sql
stable
as $$
    select
        coalesce(user_berry_balances.berries, 0)::bigint,
        coalesce(user_berry_balances.completion_streak, 0)::integer,
        user_berry_balances.last_completed_on,
        user_berry_balances.last_completed_at
    from (select auth.uid() as user_id) as berry_requester
    left join public.user_berry_balances
        on user_berry_balances.user_id = berry_requester.user_id
    where berry_requester.user_id is not null;
$$;

create function public.fetch_store_catalog()
returns table (
    id text,
    item_type text,
    item_key text,
    display_name text,
    berry_price bigint,
    is_enabled boolean,
    is_limited boolean,
    is_paid_only boolean,
    sort_order integer,
    metadata jsonb
)
security definer
set search_path = public
language sql
stable
as $$
    select
        store_items.id,
        store_items.item_type,
        store_items.item_key,
        store_items.display_name,
        store_items.berry_price,
        store_items.is_enabled,
        store_items.is_limited,
        store_items.is_paid_only,
        store_items.sort_order,
        store_items.metadata
    from public.store_items
    where store_items.is_enabled
    order by store_items.item_type, store_items.sort_order, store_items.display_name;
$$;

create function public.fetch_user_store_inventory()
returns table (
    store_item_id text,
    item_type text,
    item_key text,
    display_name text,
    berry_price bigint,
    acquired_at timestamptz,
    acquisition_source text
)
security definer
set search_path = public
language sql
stable
as $$
    select
        user_store_inventory.store_item_id,
        store_items.item_type,
        store_items.item_key,
        store_items.display_name,
        store_items.berry_price,
        user_store_inventory.acquired_at,
        user_store_inventory.acquisition_source
    from public.user_store_inventory
    join public.store_items
        on store_items.id = user_store_inventory.store_item_id
    where user_store_inventory.user_id = auth.uid()
        and store_items.is_enabled
    order by store_items.item_type, store_items.sort_order, store_items.display_name;
$$;

create function public.purchase_store_item(item_type text, item_key text)
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    owned_store_item_ids text[]
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_item_type text := lower(btrim(item_type));
    normalized_item_key text := lower(btrim(item_key));
    selected_item public.store_items%rowtype;
    current_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to buy store items.' using errcode = '28000';
    end if;

    if normalized_item_type is null or normalized_item_type not in ('hat', 'island') then
        raise exception 'Invalid store item type.' using errcode = '22023';
    end if;

    if normalized_item_key is null or normalized_item_key = '' then
        raise exception 'Invalid store item.' using errcode = '22023';
    end if;

    select *
    into selected_item
    from public.store_items
    where store_items.item_type = normalized_item_type
        and store_items.item_key = normalized_item_key
        and store_items.is_enabled
    for update;

    if not found then
        raise exception 'Store item is not available.' using errcode = 'P0002';
    end if;

    if selected_item.is_paid_only then
        raise exception 'This store item cannot be bought with berries.' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.user_store_inventory
        where user_store_inventory.user_id = requester
            and user_store_inventory.store_item_id = selected_item.id
    ) then
        raise exception 'You already own that item.' using errcode = '23505';
    end if;

    insert into public.user_berry_balances (user_id)
    values (requester)
    on conflict (user_id) do nothing;

    select *
    into current_balance
    from public.user_berry_balances
    where user_id = requester
    for update;

    if current_balance.berries < selected_item.berry_price then
        raise exception 'Not enough berries.' using errcode = '22003';
    end if;

    update public.user_berry_balances
    set berries = public.user_berry_balances.berries - selected_item.berry_price
    where public.user_berry_balances.user_id = requester
    returning * into current_balance;

    insert into public.user_store_inventory (user_id, store_item_id, acquisition_source)
    values (requester, selected_item.id, 'berries');

    return query
    select
        current_balance.berries,
        current_balance.completion_streak,
        current_balance.last_completed_on,
        current_balance.last_completed_at,
        coalesce(
            array_agg(user_store_inventory.store_item_id order by store_items.item_type, store_items.sort_order)
                filter (where user_store_inventory.store_item_id is not null),
            array[]::text[]
        )
    from (select requester as user_id) as purchase_owner
    left join public.user_store_inventory
        on user_store_inventory.user_id = purchase_owner.user_id
    left join public.store_items
        on store_items.id = user_store_inventory.store_item_id
    group by purchase_owner.user_id;
end;
$$;

create function public.award_villager_completion_pairs(
    target_session_id uuid,
    completing_user_id uuid,
    completed_at timestamptz
)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
    completed_peer_id uuid;
    user_one uuid;
    user_two uuid;
    completing_user_village_id uuid;
    peer_village_id uuid;
begin
    select id
    into completing_user_village_id
    from public.villages
    where owner_id = completing_user_id;

    if completing_user_village_id is null then
        insert into public.villages (owner_id)
        values (completing_user_id)
        on conflict (owner_id) do update
        set owner_id = excluded.owner_id
        returning id into completing_user_village_id;
    end if;

    for completed_peer_id in
        select session_events.user_id
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.event_type = 'member_completed'
            and session_events.user_id <> completing_user_id
    loop
        user_one := least(completing_user_id, completed_peer_id);
        user_two := greatest(completing_user_id, completed_peer_id);

        insert into public.villager_bonds (
            user_one_id,
            user_two_id,
            completed_pair_sessions,
            first_completed_at,
            last_completed_at
        )
        values (user_one, user_two, 1, completed_at, completed_at)
        on conflict (user_one_id, user_two_id) do update
        set completed_pair_sessions = public.villager_bonds.completed_pair_sessions + 1,
            first_completed_at = least(public.villager_bonds.first_completed_at, excluded.first_completed_at),
            last_completed_at = greatest(public.villager_bonds.last_completed_at, excluded.last_completed_at);

        insert into public.village_residents (
            village_id,
            resident_user_id,
            first_completed_session_id,
            unlocked_at
        )
        values (completing_user_village_id, completed_peer_id, target_session_id, completed_at)
        on conflict (village_id, resident_user_id) do nothing;

        select id
        into peer_village_id
        from public.villages
        where owner_id = completed_peer_id;

        if peer_village_id is null then
            insert into public.villages (owner_id)
            values (completed_peer_id)
            on conflict (owner_id) do update
            set owner_id = excluded.owner_id
            returning id into peer_village_id;
        end if;

        insert into public.village_residents (
            village_id,
            resident_user_id,
            first_completed_session_id,
            unlocked_at
        )
        values (peer_village_id, completing_user_id, target_session_id, completed_at)
        on conflict (village_id, resident_user_id) do nothing;
    end loop;
end;
$$;

create function public.list_village_residents()
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_config jsonb,
    bond_level integer,
    completed_pair_sessions integer,
    unlocked_at timestamptz
)
security definer
set search_path = public
language sql
stable
as $$
    select
        resident_profiles.user_id,
        resident_profiles.username,
        resident_profiles.display_name,
        resident_profiles.avatar_config,
        public.villager_bond_level(coalesce(villager_bonds.completed_pair_sessions, 0)) as bond_level,
        coalesce(villager_bonds.completed_pair_sessions, 0) as completed_pair_sessions,
        village_residents.unlocked_at
    from public.villages
    join public.village_residents
        on village_residents.village_id = villages.id
    join public.user_profiles as resident_profiles
        on resident_profiles.user_id = village_residents.resident_user_id
    left join public.villager_bonds
        on villager_bonds.user_one_id = least(villages.owner_id, village_residents.resident_user_id)
        and villager_bonds.user_two_id = greatest(villages.owner_id, village_residents.resident_user_id)
    where villages.owner_id = auth.uid()
    order by
        coalesce(villager_bonds.completed_pair_sessions, 0) desc,
        village_residents.unlocked_at desc,
        resident_profiles.display_name,
        resident_profiles.username;
$$;

create function public.random_fish_catches_with_rarity_bonus(
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
    into rare_pool_total_weight, boosted_rare_pool_total_weight
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

            select weighted_critters.id, weighted_critters.rarity, weighted_critters.sell_value
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
                    ) over (order by sea_critters.sort_order, sea_critters.id) as cumulative_weight
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

            select weighted_critters.id, weighted_critters.rarity, weighted_critters.sell_value
            into selected_critter
            from (
                select
                    sea_critters.id,
                    sea_critters.rarity,
                    sea_critters.sell_value,
                    sum(sea_critters.drop_weight) over (order by sea_critters.sort_order, sea_critters.id) as cumulative_weight
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

create function public.create_focus_session_fish_catches(
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
    into selected_island_id, session_duration_seconds
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
    from public.random_fish_catches_with_rarity_bonus(selected_island_id, catch_count, session_duration_seconds)
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

create function public.upsert_daily_village_snapshot(
    completing_user_id uuid,
    target_session_id uuid,
    completed_at timestamptz
)
returns public.daily_village_snapshots
security definer
set search_path = public, private
language plpgsql
as $$
declare
    snapshot_timezone text;
    computed_snapshot_day date;
    selected_island_id text;
    captured_owner_profile jsonb;
    captured_visitors jsonb;
    upserted_snapshot public.daily_village_snapshots%rowtype;
begin
    if completing_user_id is null then
        raise exception 'Completing user is required.' using errcode = '22023';
    end if;

    if target_session_id is null then
        raise exception 'Target session is required.' using errcode = '22023';
    end if;

    if completed_at is null then
        raise exception 'Completion time is required.' using errcode = '22023';
    end if;

    select private.user_profiles.user_timezone
    into snapshot_timezone
    from private.user_profiles
    where private.user_profiles.user_id = completing_user_id;

    if snapshot_timezone is null or not exists (
        select 1
        from pg_timezone_names
        where name = snapshot_timezone
    ) then
        snapshot_timezone := 'UTC';
    end if;

    computed_snapshot_day := (completed_at at time zone snapshot_timezone)::date;

    select jsonb_build_object(
        'user_id', user_profiles.user_id,
        'username', user_profiles.username,
        'display_name', user_profiles.display_name,
        'avatar_config', user_profiles.avatar_config
    )
    into captured_owner_profile
    from public.user_profiles
    where user_profiles.user_id = completing_user_id;

    if captured_owner_profile is null then
        raise exception 'No public profile was found for user %.', completing_user_id using errcode = 'P0002';
    end if;

    select session_members.island_id
    into selected_island_id
    from public.session_members
    join public.islands
        on islands.id = session_members.island_id
        and islands.is_enabled
    where session_members.session_id = target_session_id
        and session_members.user_id = completing_user_id
        and session_members.status = 'joined';

    if selected_island_id is null then
        raise exception 'No enabled island is stored for user % in focus session %.', completing_user_id, target_session_id using errcode = 'P0002';
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'user_id', peer_profiles.user_id,
                'username', peer_profiles.username,
                'display_name', peer_profiles.display_name,
                'avatar_config', peer_profiles.avatar_config,
                'bond_level', public.villager_bond_level(coalesce(villager_bonds.completed_pair_sessions, 0)),
                'completed_pair_sessions', coalesce(villager_bonds.completed_pair_sessions, 0)
            )
            order by peer_profiles.display_name, peer_profiles.username, peer_profiles.user_id
        ),
        '[]'::jsonb
    )
    into captured_visitors
    from public.focus_sessions
    join public.session_members as peer_members
        on peer_members.session_id = focus_sessions.id
    join public.user_profiles as peer_profiles
        on peer_profiles.user_id = peer_members.user_id
    left join public.villager_bonds
        on villager_bonds.user_one_id = least(completing_user_id, peer_members.user_id)
        and villager_bonds.user_two_id = greatest(completing_user_id, peer_members.user_id)
    where focus_sessions.id = target_session_id
        and focus_sessions.mode = 'multiplayer'
        and peer_members.user_id <> completing_user_id
        and peer_members.status = 'joined';

    insert into public.daily_village_snapshots (
        owner_id,
        snapshot_day,
        user_timezone,
        island_id,
        owner_profile,
        visitors,
        focus_session_ids
    )
    values (
        completing_user_id,
        computed_snapshot_day,
        snapshot_timezone,
        selected_island_id,
        captured_owner_profile,
        captured_visitors,
        array[target_session_id]::uuid[]
    )
    on conflict (owner_id, snapshot_day) do update
    set visitors = public.merge_daily_village_snapshot_visitors(
            public.daily_village_snapshots.visitors,
            excluded.visitors
        ),
        focus_session_ids = public.merge_daily_village_snapshot_focus_session_ids(
            public.daily_village_snapshots.focus_session_ids,
            excluded.focus_session_ids
        )
    returning * into upserted_snapshot;

    return upserted_snapshot;
end;
$$;

create function public.create_focus_session(
    session_mode text default 'solo',
    duration_seconds integer default 1800,
    island_id text default 'default'
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    new_session_id uuid;
    normalized_island_id text := coalesce(nullif(lower(btrim(island_id)), ''), 'default');
    normalized_mode text := lower(btrim(session_mode));
begin
    if requester is null then
        raise exception 'You must be signed in to create a focus session.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));
    perform public.reconcile_open_focus_sessions();

    if normalized_mode is null or normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 600 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 minutes and 24 hours.' using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = normalized_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', normalized_island_id using errcode = '22023';
    end if;

    if not public.user_owns_island(requester, normalized_island_id) then
        raise exception 'You do not own that island.' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and (
                focus_sessions.status = 'lobby'
                or (
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                    and focus_sessions.planned_end_at > now()
                    and not exists (
                        select 1
                        from public.session_events
                        where session_events.session_id = focus_sessions.id
                            and session_events.user_id = requester
                            and session_events.event_type in ('member_completed', 'member_interrupted')
                    )
                )
            )
    ) then
        raise exception 'You already have an open focus session.' using errcode = '23505';
    end if;

    insert into public.focus_sessions (owner_id, mode, duration_seconds)
    values (requester, normalized_mode, duration_seconds)
    returning id into new_session_id;

    insert into public.session_members (session_id, user_id, island_id, role, status)
    values (new_session_id, requester, normalized_island_id, 'host', 'joined');

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
end;
$$;

create function public.update_focus_session_config(target_session_id uuid, duration_seconds integer)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to update a focus session.' using errcode = '28000';
    end if;

    if duration_seconds is null or duration_seconds < 600 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 minutes and 24 hours.' using errcode = '22023';
    end if;

    update public.focus_sessions
    set duration_seconds = update_focus_session_config.duration_seconds
    where id = target_session_id
        and owner_id = requester
        and status = 'lobby'
        and exists (
            select 1
            from public.session_members
            where session_members.session_id = target_session_id
                and session_members.user_id = requester
                and session_members.role = 'host'
                and session_members.status = 'joined'
        );

    if not found then
        raise exception 'No configurable focus lobby was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.invite_focus_session_members(target_session_id uuid, invitee_ids uuid[])
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    invitee uuid;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to invite members.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and owner_id = requester
    for update;

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.mode <> 'multiplayer' then
        raise exception 'Only multiplayer sessions can invite members.' using errcode = '22023';
    end if;

    foreach invitee in array coalesce(invitee_ids, array[]::uuid[])
    loop
        if invitee = requester then
            raise exception 'You cannot invite yourself.' using errcode = '22023';
        end if;

        if not exists (
            select 1
            from public.friendships
            where friendships.user_one_id = least(requester, invitee)
                and friendships.user_two_id = greatest(requester, invitee)
        ) then
            raise exception 'Only friends can be invited to a focus session.' using errcode = '22023';
        end if;

        insert into public.session_members (session_id, user_id, role, status)
        values (target_session_id, invitee, 'participant', 'invited')
        on conflict (session_id, user_id) do update
        set status = case
                when session_members.status = 'joined' then session_members.status
                else 'invited'
            end,
            role = 'participant';
    end loop;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.join_focus_session(target_session_id uuid, island_id text default 'default')
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_island_id text := coalesce(nullif(lower(btrim(island_id)), ''), 'default');
    session_record public.focus_sessions%rowtype;
    membership_record public.session_members%rowtype;
    joined_now boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to join a focus session.' using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = normalized_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', normalized_island_id using errcode = '22023';
    end if;

    if not public.user_owns_island(requester, normalized_island_id) then
        raise exception 'You do not own that island.' using errcode = '42501';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    select *
    into membership_record
    from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status in ('invited', 'joined', 'left')
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if session_record.status = 'cancelled' then
        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined');

        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    if membership_record.status = 'invited' then
        update public.session_members
        set status = 'joined',
            island_id = normalized_island_id
        where session_id = target_session_id
            and user_id = requester
            and status = 'invited';

        joined_now := found;
    end if;

    if membership_record.status <> 'joined' and not joined_now then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if joined_now then
        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_joined');
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.decline_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    has_membership boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to decline a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    select exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined', 'left')
    )
    into has_membership;

    if not has_membership then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'invited';

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.start_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    starts_at timestamptz := now();
    next_status text;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to start a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and owner_id = requester
        and exists (
            select 1
            from public.session_members
            where session_members.session_id = target_session_id
                and session_members.user_id = requester
                and session_members.role = 'host'
                and session_members.status = 'joined'
        )
    for update;

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.status in ('launched', 'live') then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'multiplayer' and not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and role <> 'host'
            and status = 'joined'
    ) then
        raise exception 'At least one invited member must join before starting.' using errcode = '22023';
    end if;

    next_status := case
        when session_record.mode = 'multiplayer' then 'launched'
        else 'live'
    end;

    update public.focus_sessions
    set status = next_status,
        started_at = starts_at,
        planned_end_at = starts_at + make_interval(secs => duration_seconds)
    where id = target_session_id
        and status = 'lobby';

    delete from public.session_members
    where session_id = target_session_id
        and status = 'invited';

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'session_started');

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.complete_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    finished_at timestamptz := now();
    completion_recorded_at timestamptz;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to complete a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_completed'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    if not (
        session_record.status in ('live', 'completed')
        or (session_record.mode = 'multiplayer' and session_record.status = 'launched')
    ) then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined'
    ) then
        raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'multiplayer' and exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_interrupted'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.planned_end_at is null or session_record.planned_end_at > finished_at then
        raise exception 'Focus session is not complete yet.' using errcode = '42501';
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.record_user_completion_streak(requester, completion_recorded_at);
        perform public.create_focus_session_fish_catches(requester, target_session_id, completion_recorded_at);
        perform public.award_villager_completion_pairs(target_session_id, requester, completion_recorded_at);
        perform public.upsert_daily_village_snapshot(requester, target_session_id, completion_recorded_at);
    end if;

    if session_record.status = 'live' and session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.cancel_session_lobby(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to cancel a focus lobby.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and owner_id = requester
        and exists (
            select 1
            from public.session_members
            where session_members.session_id = target_session_id
                and session_members.user_id = requester
                and session_members.role = 'host'
                and session_members.status = 'joined'
        )
    for update;

    if not found then
        raise exception 'No cancellable focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    update public.focus_sessions
    set status = 'cancelled',
        ended_at = now()
    where id = target_session_id
        and status = 'lobby';

    update public.session_members
    set status = 'left'
    where session_id = target_session_id;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.leave_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    membership_record public.session_members%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to leave a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and status in ('lobby', 'launched', 'live')
    for update;

    if not found then
        raise exception 'No open focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.mode <> 'multiplayer' then
        raise exception 'Only multiplayer sessions can be left.' using errcode = '22023';
    end if;

    select *
    into membership_record
    from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined'
    for update;

    if not found then
        raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
    end if;

    if membership_record.role = 'host' or session_record.owner_id = requester then
        raise exception 'The host must cancel the focus session instead.' using errcode = '42501';
    end if;

    if session_record.status = 'lobby' then
        delete from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined';
    else
        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined';

        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_interrupted')
        on conflict do nothing;

        if not exists (
            select 1
            from public.session_members
            where session_id = target_session_id
                and status = 'joined'
        ) then
            update public.focus_sessions
            set status = 'interrupted',
                ended_at = now()
            where id = target_session_id
                and status in ('launched', 'live');
        end if;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.interrupt_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to interrupt a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and (
            status in ('live', 'interrupted')
            or (mode = 'multiplayer' and status = 'launched')
        )
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'solo' and session_record.owner_id <> requester then
        raise exception 'Only the host can interrupt a solo focus session.' using errcode = '42501';
    end if;

    if session_record.status = 'interrupted' then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'interrupted',
            ended_at = now()
        where id = target_session_id;
    else
        if not exists (
            select 1
            from public.session_members
            where session_id = target_session_id
                and user_id = requester
                and status = 'joined'
        ) then
            raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
        end if;

        if exists (
            select 1
            from public.session_events
            where session_events.session_id = target_session_id
                and session_events.user_id = requester
                and session_events.event_type = 'member_completed'
        ) then
            return public.focus_session_payload(target_session_id);
        end if;
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_interrupted')
    on conflict do nothing;

    return public.focus_session_payload(target_session_id);
end;
$$;

create function public.reconcile_open_focus_sessions()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    reconciled_at timestamptz := now();
    stale_lobby_after interval := interval '24 hours';
    session_record record;
    completion_recorded_at timestamptz;
    completed_count integer := 0;
    cancelled_lobby_count integer := 0;
    left_lobby_count integer := 0;
    repaired_cancelled_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to reconcile focus sessions.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));

    update public.session_members
    set status = 'left'
    from public.focus_sessions
    where session_members.session_id = focus_sessions.id
        and session_members.user_id = requester
        and session_members.status in ('invited', 'joined')
        and focus_sessions.status = 'cancelled';

    get diagnostics repaired_cancelled_count = row_count;
    cancelled_lobby_count := cancelled_lobby_count + repaired_cancelled_count;

    for session_record in
        select focus_sessions.*, session_members.role as member_role
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.status = 'lobby'
            and focus_sessions.updated_at <= reconciled_at - stale_lobby_after
        for update of focus_sessions
    loop
        if session_record.owner_id = requester or session_record.member_role = 'host' then
            update public.focus_sessions
            set status = 'cancelled',
                ended_at = reconciled_at
            where id = session_record.id
                and status = 'lobby';

            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and status in ('invited', 'joined');

            cancelled_lobby_count := cancelled_lobby_count + 1;
        else
            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and user_id = requester
                and status = 'joined';

            left_lobby_count := left_lobby_count + 1;
        end if;
    end loop;

    for session_record in
        select focus_sessions.*
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.planned_end_at <= reconciled_at
            and (
                (focus_sessions.mode = 'solo' and focus_sessions.status = 'live')
                or (focus_sessions.mode = 'multiplayer' and focus_sessions.status = 'launched')
            )
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = focus_sessions.id
                    and session_events.user_id = requester
                    and session_events.event_type in ('member_completed', 'member_interrupted')
            )
        for update of focus_sessions
    loop
        completion_recorded_at := null;

        insert into public.session_events (session_id, user_id, event_type)
        values (session_record.id, requester, 'member_completed')
        on conflict do nothing
        returning occurred_at into completion_recorded_at;

        if completion_recorded_at is not null then
            perform public.record_user_completion_streak(requester, completion_recorded_at);
            perform public.create_focus_session_fish_catches(requester, session_record.id, completion_recorded_at);
            perform public.award_villager_completion_pairs(session_record.id, requester, completion_recorded_at);
            perform public.upsert_daily_village_snapshot(requester, session_record.id, completion_recorded_at);
        end if;

        if session_record.mode = 'solo' then
            update public.focus_sessions
            set status = 'completed',
                ended_at = greatest(reconciled_at, planned_end_at)
            where id = session_record.id
                and status = 'live';
        end if;

        completed_count := completed_count + 1;
    end loop;

    return jsonb_build_object(
        'reconciled_at', reconciled_at,
        'completed_sessions', completed_count,
        'cancelled_lobbies', cancelled_lobby_count,
        'left_lobbies', left_lobby_count
    );
end;
$$;

create function public.fetch_focus_session_detail(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
stable
as $$
declare
    requester uuid := auth.uid();
    payload jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to view a focus session.' using errcode = '28000';
    end if;

    if not public.is_focus_session_member(target_session_id) then
        raise exception 'No focus session membership was found.' using errcode = 'P0002';
    end if;

    payload := public.focus_session_detail_payload(target_session_id);

    if payload is null then
        raise exception 'No focus session was found.' using errcode = 'P0002';
    end if;

    return payload;
end;
$$;

create function public.fetch_current_focus_session_detail()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    current_session_id uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to view a focus session.' using errcode = '28000';
    end if;

    perform public.reconcile_open_focus_sessions();

    select focus_sessions.id
    into current_session_id
    from public.session_members
    join public.focus_sessions
        on focus_sessions.id = session_members.session_id
    where session_members.user_id = requester
        and session_members.status = 'joined'
        and (
            focus_sessions.status = 'lobby'
            or (
                focus_sessions.mode = 'solo'
                and focus_sessions.status = 'live'
            )
            or (
                focus_sessions.mode = 'multiplayer'
                and focus_sessions.status = 'launched'
                and focus_sessions.planned_end_at > now()
                and not exists (
                    select 1
                    from public.session_events
                    where session_events.session_id = focus_sessions.id
                        and session_events.user_id = requester
                        and session_events.event_type in ('member_completed', 'member_interrupted')
                )
            )
        )
    order by
        case
            when focus_sessions.status in ('live', 'launched') then 0
            else 1
        end,
        focus_sessions.updated_at desc
    limit 1;

    if current_session_id is null then
        return null;
    end if;

    return public.focus_session_detail_payload(current_session_id);
end;
$$;

create function public.list_incoming_focus_session_invites()
returns table (
    id uuid,
    owner_id uuid,
    mode text,
    status text,
    duration_seconds integer,
    started_at timestamptz,
    planned_end_at timestamptz,
    ended_at timestamptz,
    created_at timestamptz,
    host_user_id uuid,
    host_username text,
    host_display_name text,
    host_avatar_config jsonb
)
security definer
set search_path = public
language sql
stable
as $$
    select
        focus_sessions.id,
        focus_sessions.owner_id,
        focus_sessions.mode,
        focus_sessions.status,
        focus_sessions.duration_seconds,
        focus_sessions.started_at,
        focus_sessions.planned_end_at,
        focus_sessions.ended_at,
        focus_sessions.created_at,
        user_profiles.user_id as host_user_id,
        user_profiles.username as host_username,
        user_profiles.display_name as host_display_name,
        user_profiles.avatar_config as host_avatar_config
    from public.session_members
    join public.focus_sessions
        on focus_sessions.id = session_members.session_id
    join public.user_profiles
        on user_profiles.user_id = focus_sessions.owner_id
    where session_members.user_id = auth.uid()
        and session_members.status = 'invited'
        and focus_sessions.mode = 'multiplayer'
        and focus_sessions.status = 'lobby'
    order by focus_sessions.created_at desc;
$$;

create function public.sell_user_fish(catch_ids uuid[])
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    sold_fish_count integer,
    sold_berry_amount bigint
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    sold_time timestamptz := now();
    requested_count integer;
    distinct_requested_count integer;
    locked_count integer;
    already_sold_count integer;
    sold_amount bigint := 0;
    sold_count integer := 0;
    updated_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to sell fish.' using errcode = '28000';
    end if;

    requested_count := coalesce(cardinality(catch_ids), 0);
    if requested_count = 0 then
        raise exception 'Choose at least one fish to sell.' using errcode = '22023';
    end if;

    select count(distinct requested_catch_id)
    into distinct_requested_count
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    if distinct_requested_count <> requested_count then
        raise exception 'Fish can only be sold once per request.' using errcode = '22023';
    end if;

    drop table if exists pg_temp.requested_fish_sale_ids;
    drop table if exists pg_temp.locked_fish_sale_rows;

    create temporary table requested_fish_sale_ids (
        id uuid primary key
    ) on commit drop;

    insert into requested_fish_sale_ids (id)
    select requested_catch_id
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    create temporary table locked_fish_sale_rows
    on commit drop
    as
    select user_fish_catches.*
    from public.user_fish_catches
    join requested_fish_sale_ids
        on requested_fish_sale_ids.id = user_fish_catches.id
    where user_fish_catches.user_id = requester
    for update of user_fish_catches;

    select count(*)
    into locked_count
    from locked_fish_sale_rows;

    if locked_count <> requested_count then
        raise exception 'One or more selected fish could not be found.' using errcode = 'P0002';
    end if;

    select count(*)
    into already_sold_count
    from locked_fish_sale_rows
    where sold_at is not null;

    if already_sold_count > 0 then
        raise exception 'One or more selected fish has already been sold.' using errcode = '23514';
    end if;

    with sold_rows as (
        update public.user_fish_catches
        set sold_at = sold_time,
            sold_for_berries = public.user_fish_catches.sell_value
        from requested_fish_sale_ids
        where public.user_fish_catches.id = requested_fish_sale_ids.id
            and public.user_fish_catches.user_id = requester
            and public.user_fish_catches.sold_at is null
        returning public.user_fish_catches.sell_value
    )
    select count(*)::integer, coalesce(sum(sell_value), 0)::bigint
    into sold_count, sold_amount
    from sold_rows;

    if sold_count <> requested_count then
        raise exception 'One or more selected fish could not be sold.' using errcode = '40001';
    end if;

    insert into public.user_berry_balances (user_id, berries)
    values (requester, sold_amount)
    on conflict (user_id) do update
    set berries = public.user_berry_balances.berries + excluded.berries
    returning * into updated_balance;

    return query
    select
        updated_balance.berries,
        updated_balance.completion_streak,
        updated_balance.last_completed_on,
        updated_balance.last_completed_at,
        sold_count,
        sold_amount;
end;
$$;

create function public.fetch_user_fish_collection_counts(island_id text default 'default')
returns table (
    sea_critter_id text,
    display_name text,
    rarity text,
    sell_value bigint,
    asset_name text,
    sort_order integer,
    count integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    selected_island_id text := coalesce(nullif(lower(btrim($1)), ''), 'default');
begin
    if requester is null then
        raise exception 'You must be signed in to view fish collection counts.' using errcode = '28000';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = selected_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', selected_island_id using errcode = 'P0002';
    end if;

    return query
    select
        sea_critters.id as sea_critter_id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order,
        count(user_fish_catches.id)::integer as count
    from public.island_sea_critters
    join public.sea_critters
        on sea_critters.id = island_sea_critters.sea_critter_id
    left join public.user_fish_catches
        on user_fish_catches.sea_critter_id = sea_critters.id
        and user_fish_catches.user_id = requester
    where island_sea_critters.island_id = selected_island_id
        and island_sea_critters.is_enabled
        and sea_critters.is_enabled
    group by
        sea_critters.id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order
    order by sea_critters.sort_order;
end;
$$;

create function public.fetch_user_fish_inventory_counts()
returns table (
    sea_critter_id text,
    display_name text,
    rarity text,
    sell_value bigint,
    asset_name text,
    sort_order integer,
    count integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to view fish inventory counts.' using errcode = '28000';
    end if;

    return query
    select
        sea_critters.id as sea_critter_id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order,
        count(user_fish_catches.id)::integer as count
    from public.user_fish_catches
    join public.sea_critters
        on sea_critters.id = user_fish_catches.sea_critter_id
    where user_fish_catches.user_id = requester
        and user_fish_catches.sold_at is null
    group by
        sea_critters.id,
        sea_critters.display_name,
        sea_critters.rarity,
        sea_critters.sell_value,
        sea_critters.asset_name,
        sea_critters.sort_order
    order by sea_critters.sort_order;
end;
$$;

create function public.list_daily_village_snapshots(start_day date, end_day date)
returns table (
    owner_id uuid,
    snapshot_day date,
    user_timezone text,
    island_id text,
    owner_profile jsonb,
    visitors jsonb,
    focus_session_ids uuid[],
    total_focus_seconds integer,
    fish_caught_count integer,
    created_at timestamptz,
    updated_at timestamptz
)
security definer
stable
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to list daily village snapshots.' using errcode = '28000';
    end if;

    if start_day is null or end_day is null then
        raise exception 'Snapshot range dates are required.' using errcode = '22023';
    end if;

    if end_day < start_day then
        raise exception 'Snapshot range end_day must be on or after start_day.' using errcode = '22023';
    end if;

    return query
    select
        snapshots.owner_id,
        snapshots.snapshot_day,
        snapshots.user_timezone,
        snapshots.island_id,
        snapshots.owner_profile,
        snapshots.visitors,
        snapshots.focus_session_ids,
        coalesce(focus_totals.total_focus_seconds, 0) as total_focus_seconds,
        coalesce(fish_totals.fish_caught_count, 0) as fish_caught_count,
        snapshots.created_at,
        snapshots.updated_at
    from public.daily_village_snapshots as snapshots
    left join lateral (
        select sum(focus_sessions.duration_seconds)::integer as total_focus_seconds
        from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
        join public.focus_sessions
            on focus_sessions.id = snapshot_sessions.session_id
    ) as focus_totals on true
    left join lateral (
        select count(user_fish_catches.id)::integer as fish_caught_count
        from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
        join public.user_fish_catches
            on user_fish_catches.session_id = snapshot_sessions.session_id
            and user_fish_catches.user_id = snapshots.owner_id
    ) as fish_totals on true
    where snapshots.owner_id = requester
        and snapshots.snapshot_day between start_day and end_day
    order by snapshots.snapshot_day desc;
end;
$$;

create function public.fetch_daily_village_snapshot(requested_snapshot_day date)
returns table (
    owner_id uuid,
    snapshot_day date,
    user_timezone text,
    island_id text,
    owner_profile jsonb,
    visitors jsonb,
    focus_session_ids uuid[],
    total_focus_seconds integer,
    fish_caught_count integer,
    fish_counts jsonb,
    created_at timestamptz,
    updated_at timestamptz
)
security definer
stable
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to fetch a daily village snapshot.' using errcode = '28000';
    end if;

    if requested_snapshot_day is null then
        raise exception 'Snapshot day is required.' using errcode = '22023';
    end if;

    return query
    select
        snapshots.owner_id,
        snapshots.snapshot_day,
        snapshots.user_timezone,
        snapshots.island_id,
        snapshots.owner_profile,
        snapshots.visitors,
        snapshots.focus_session_ids,
        coalesce(focus_totals.total_focus_seconds, 0) as total_focus_seconds,
        coalesce(fish_totals.fish_caught_count, 0) as fish_caught_count,
        coalesce(fish_totals.fish_counts, '[]'::jsonb) as fish_counts,
        snapshots.created_at,
        snapshots.updated_at
    from public.daily_village_snapshots as snapshots
    left join lateral (
        select sum(focus_sessions.duration_seconds)::integer as total_focus_seconds
        from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
        join public.focus_sessions
            on focus_sessions.id = snapshot_sessions.session_id
    ) as focus_totals on true
    left join lateral (
        select
            coalesce(sum(fish_groups.catch_count), 0)::integer as fish_caught_count,
            coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'sea_critter_id', fish_groups.sea_critter_id,
                        'display_name', fish_groups.display_name,
                        'rarity', fish_groups.rarity,
                        'sell_value', fish_groups.sell_value,
                        'asset_name', fish_groups.asset_name,
                        'sort_order', fish_groups.sort_order,
                        'count', fish_groups.catch_count
                    )
                    order by fish_groups.sort_order, fish_groups.sea_critter_id
                ),
                '[]'::jsonb
            ) as fish_counts
        from (
            select
                sea_critters.id as sea_critter_id,
                sea_critters.display_name,
                sea_critters.rarity,
                sea_critters.sell_value::integer as sell_value,
                sea_critters.asset_name,
                sea_critters.sort_order,
                count(user_fish_catches.id)::integer as catch_count
            from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
            join public.user_fish_catches
                on user_fish_catches.session_id = snapshot_sessions.session_id
                and user_fish_catches.user_id = snapshots.owner_id
            join public.sea_critters
                on sea_critters.id = user_fish_catches.sea_critter_id
            group by
                sea_critters.id,
                sea_critters.display_name,
                sea_critters.rarity,
                sea_critters.sell_value,
                sea_critters.asset_name,
                sea_critters.sort_order
        ) as fish_groups
    ) as fish_totals on true
    where snapshots.owner_id = requester
        and snapshots.snapshot_day = requested_snapshot_day;
end;
$$;

create function public.list_daily_focus_activity(start_day date, end_day date)
returns table (
    snapshot_day date,
    has_focus boolean
)
security definer
stable
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to list daily focus activity.' using errcode = '28000';
    end if;

    if start_day is null or end_day is null then
        raise exception 'Activity range dates are required.' using errcode = '22023';
    end if;

    if end_day < start_day then
        raise exception 'Activity range end_day must be on or after start_day.' using errcode = '22023';
    end if;

    if end_day > start_day + 62 then
        raise exception 'Activity range cannot exceed 63 days.' using errcode = '22023';
    end if;

    return query
    with requested_days as (
        select generate_series(start_day, end_day, interval '1 day')::date as snapshot_day
    )
    select
        requested_days.snapshot_day,
        exists (
            select 1
            from public.daily_village_snapshots as snapshots
            join lateral unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
                on true
            join public.focus_sessions
                on focus_sessions.id = snapshot_sessions.session_id
                and focus_sessions.duration_seconds > 0
            where snapshots.owner_id = requester
                and snapshots.snapshot_day = requested_days.snapshot_day
        ) as has_focus
    from requested_days
    order by requested_days.snapshot_day asc;
end;
$$;

create function public.is_email_available(target_email text)
returns boolean
language sql
security definer
set search_path = ''
as $$
    select not exists (
        select 1
        from auth.users
        where lower(auth.users.email) = lower(btrim(target_email))
        limit 1
    );
$$;

alter table public.users enable row level security;
alter table public.user_profiles enable row level security;
alter table private.user_profiles enable row level security;
alter table public.sea_critters enable row level security;
alter table public.islands enable row level security;
alter table public.island_sea_critters enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.focus_sessions enable row level security;
alter table public.session_members enable row level security;
alter table public.session_events enable row level security;
alter table public.villages enable row level security;
alter table public.village_residents enable row level security;
alter table public.villager_bonds enable row level security;
alter table public.user_berry_balances enable row level security;
alter table public.store_items enable row level security;
alter table public.user_store_inventory enable row level security;
alter table public.user_fish_catches enable row level security;
alter table public.daily_village_snapshots enable row level security;

create policy "Anyone can read public profiles"
on public.user_profiles
for select
to anon, authenticated
using (true);

create policy "Users can insert own public profile"
on public.user_profiles
for insert
to authenticated
with check (user_id = auth.uid());

create policy "Users can update own public profile"
on public.user_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users can read own private profile"
on private.user_profiles
for select
to authenticated
using (user_id = auth.uid());

create policy "Users can update own private profile"
on private.user_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Authenticated users can read enabled sea critters"
on public.sea_critters
for select
to authenticated
using (is_enabled);

create policy "Authenticated users can read enabled islands"
on public.islands
for select
to authenticated
using (is_enabled);

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

create policy "Participants can read friend requests"
on public.friend_requests
for select
to authenticated
using (requester_id = auth.uid() or recipient_id = auth.uid());

create policy "Participants can read friendships"
on public.friendships
for select
to authenticated
using (user_one_id = auth.uid() or user_two_id = auth.uid());

create policy "Members can read focus sessions"
on public.focus_sessions
for select
to authenticated
using (public.is_focus_session_member(id));

create policy "Members can read session members"
on public.session_members
for select
to authenticated
using (public.can_read_focus_session_member(session_id, user_id));

create policy "Members can read session events"
on public.session_events
for select
to authenticated
using (public.is_focus_session_member(session_id));

create policy "Users can read own village"
on public.villages
for select
to authenticated
using (owner_id = auth.uid());

create policy "Users can read own village residents"
on public.village_residents
for select
to authenticated
using (
    exists (
        select 1
        from public.villages
        where villages.id = village_residents.village_id
            and villages.owner_id = auth.uid()
    )
);

create policy "Users can read own villager bonds"
on public.villager_bonds
for select
to authenticated
using (user_one_id = auth.uid() or user_two_id = auth.uid());

create policy "Users can read own berry balance"
on public.user_berry_balances
for select
to authenticated
using (user_id = auth.uid());

create policy "Authenticated users can read enabled store items"
on public.store_items
for select
to authenticated
using (is_enabled);

create policy "Users can read own store inventory"
on public.user_store_inventory
for select
to authenticated
using (user_id = auth.uid());

create policy "Users can read own fish catches"
on public.user_fish_catches
for select
to authenticated
using (user_id = auth.uid());

create policy "Users can read own daily village snapshots"
on public.daily_village_snapshots
for select
to authenticated
using (owner_id = auth.uid());

revoke all on public.users from public, anon, authenticated;
revoke all on public.user_profiles from public, anon, authenticated;
revoke all on private.user_profiles from public, anon, authenticated;
revoke all on public.sea_critters from public, anon, authenticated;
revoke all on public.islands from public, anon, authenticated;
revoke all on public.island_sea_critters from public, anon, authenticated;
revoke all on public.friend_requests from public, anon, authenticated;
revoke all on public.friendships from public, anon, authenticated;
revoke all on public.focus_sessions from public, anon, authenticated;
revoke all on public.session_members from public, anon, authenticated;
revoke all on public.session_events from public, anon, authenticated;
revoke all on public.villages from public, anon, authenticated;
revoke all on public.village_residents from public, anon, authenticated;
revoke all on public.villager_bonds from public, anon, authenticated;
revoke all on public.user_berry_balances from public, anon, authenticated;
revoke all on public.store_items from public, anon, authenticated;
revoke all on public.user_store_inventory from public, anon, authenticated;
revoke all on public.user_fish_catches from public, anon, authenticated;
revoke all on public.daily_village_snapshots from public, anon, authenticated;

grant usage on schema private to authenticated;
grant select on public.user_profiles to anon, authenticated;
grant insert, update on public.user_profiles to authenticated;
grant select, update on private.user_profiles to authenticated;
grant select on public.sea_critters to authenticated;
grant select on public.islands to authenticated;
grant select on public.island_sea_critters to authenticated;
grant select on public.friend_requests to authenticated;
grant select on public.friendships to authenticated;
grant select on public.focus_sessions to authenticated;
grant select on public.session_members to authenticated;
grant select on public.session_events to authenticated;
grant select on public.villages to authenticated;
grant select on public.village_residents to authenticated;
grant select on public.villager_bonds to authenticated;
grant select on public.user_berry_balances to authenticated;
grant select on public.store_items to authenticated;
grant select on public.user_store_inventory to authenticated;
grant select on public.user_fish_catches to authenticated;
grant select on public.daily_village_snapshots to authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
        execute 'grant execute on function public.validate_avatar_config(jsonb) to supabase_auth_admin';
    end if;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.validate_avatar_config(jsonb) from public, anon, authenticated;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.validate_enabled_island_sea_critter() from public, anon, authenticated;
revoke all on function public.prevent_disabling_enabled_island_sea_critter() from public, anon, authenticated;
revoke all on function public.reject_session_events_mutation() from public, anon, authenticated;
revoke all on function public.villager_bond_level(integer) from public, anon, authenticated;
revoke all on function public.ensure_user_village() from public, anon, authenticated;
revoke all on function public.validate_session_member_island() from public, anon, authenticated;
revoke all on function public.prevent_disabling_session_member_island() from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_owner_profile(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_visitors(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_focus_session_ids(uuid[]) from public, anon, authenticated;
revoke all on function public.merge_daily_village_snapshot_focus_session_ids(uuid[], uuid[]) from public, anon, authenticated;
revoke all on function public.merge_daily_village_snapshot_visitors(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_references() from public, anon, authenticated;
revoke all on function public.prevent_daily_village_snapshot_identity_update() from public, anon, authenticated;
revoke all on function public.user_owns_store_item(uuid, text, text) from public, anon, authenticated;
revoke all on function public.user_owns_avatar_hat(uuid, integer) from public, anon, authenticated;
revoke all on function public.user_owns_island(uuid, text) from public, anon, authenticated;
revoke all on function public.enforce_avatar_hat_ownership() from public, anon, authenticated;
revoke all on function public.is_focus_session_member(uuid) from public, anon, authenticated;
revoke all on function public.can_read_focus_session_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.focus_session_payload(uuid) from public, anon, authenticated;
revoke all on function public.focus_session_detail_payload(uuid) from public, anon, authenticated;
revoke all on function public.set_user_timezone(text) from public, anon, authenticated;
revoke all on function public.send_friend_request(text) from public, anon, authenticated;
revoke all on function public.accept_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.reject_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.list_incoming_friend_requests() from public, anon, authenticated;
revoke all on function public.list_friends() from public, anon, authenticated;
revoke all on function public.record_user_completion_streak(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.fetch_user_berries() from public, anon, authenticated;
revoke all on function public.fetch_store_catalog() from public, anon, authenticated;
revoke all on function public.fetch_user_store_inventory() from public, anon, authenticated;
revoke all on function public.purchase_store_item(text, text) from public, anon, authenticated;
revoke all on function public.award_villager_completion_pairs(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.list_village_residents() from public, anon, authenticated;
revoke all on function public.random_fish_catches_with_rarity_bonus(text, integer, integer) from public, anon, authenticated;
revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.upsert_daily_village_snapshot(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.create_focus_session(text, integer, text) from public, anon, authenticated;
revoke all on function public.update_focus_session_config(uuid, integer) from public, anon, authenticated;
revoke all on function public.invite_focus_session_members(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.join_focus_session(uuid, text) from public, anon, authenticated;
revoke all on function public.decline_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.start_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.cancel_session_lobby(uuid) from public, anon, authenticated;
revoke all on function public.leave_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.interrupt_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;
revoke all on function public.fetch_focus_session_detail(uuid) from public, anon, authenticated;
revoke all on function public.fetch_current_focus_session_detail() from public, anon, authenticated;
revoke all on function public.list_incoming_focus_session_invites() from public, anon, authenticated;
revoke all on function public.sell_user_fish(uuid[]) from public, anon, authenticated;
revoke all on function public.fetch_user_fish_collection_counts(text) from public, anon, authenticated;
revoke all on function public.fetch_user_fish_inventory_counts() from public, anon, authenticated;
revoke all on function public.list_daily_village_snapshots(date, date) from public, anon, authenticated;
revoke all on function public.fetch_daily_village_snapshot(date) from public, anon, authenticated;
revoke all on function public.list_daily_focus_activity(date, date) from public, anon, authenticated;
revoke all on function public.is_email_available(text) from public, anon, authenticated;

grant execute on function public.validate_avatar_config(jsonb) to authenticated;
grant execute on function public.set_user_timezone(text) to authenticated;
grant execute on function public.fetch_user_berries() to authenticated;
grant execute on function public.fetch_store_catalog() to authenticated;
grant execute on function public.fetch_user_store_inventory() to authenticated;
grant execute on function public.purchase_store_item(text, text) to authenticated;
grant execute on function public.is_focus_session_member(uuid) to authenticated;
grant execute on function public.can_read_focus_session_member(uuid, uuid) to authenticated;
grant execute on function public.list_village_residents() to authenticated;
grant execute on function public.create_focus_session(text, integer, text) to authenticated;
grant execute on function public.update_focus_session_config(uuid, integer) to authenticated;
grant execute on function public.invite_focus_session_members(uuid, uuid[]) to authenticated;
grant execute on function public.join_focus_session(uuid, text) to authenticated;
grant execute on function public.decline_focus_session(uuid) to authenticated;
grant execute on function public.start_focus_session(uuid) to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.cancel_session_lobby(uuid) to authenticated;
grant execute on function public.leave_focus_session(uuid) to authenticated;
grant execute on function public.interrupt_focus_session(uuid) to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;
grant execute on function public.fetch_focus_session_detail(uuid) to authenticated;
grant execute on function public.fetch_current_focus_session_detail() to authenticated;
grant execute on function public.list_incoming_focus_session_invites() to authenticated;
grant execute on function public.sell_user_fish(uuid[]) to authenticated;
grant execute on function public.fetch_user_fish_collection_counts(text) to authenticated;
grant execute on function public.fetch_user_fish_inventory_counts() to authenticated;
grant execute on function public.list_daily_village_snapshots(date, date) to authenticated;
grant execute on function public.fetch_daily_village_snapshot(date) to authenticated;
grant execute on function public.list_daily_focus_activity(date, date) to authenticated;
grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.reject_friend_request(uuid) to authenticated;
grant execute on function public.list_incoming_friend_requests() to authenticated;
grant execute on function public.list_friends() to authenticated;
grant execute on function public.is_email_available(text) to anon, authenticated;

do $$
begin
    if exists (
        select 1
        from pg_publication
        where pubname = 'supabase_realtime'
    ) then
        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
                and schemaname = 'public'
                and tablename = 'focus_sessions'
        ) then
            alter publication supabase_realtime add table public.focus_sessions;
        end if;

        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
                and schemaname = 'public'
                and tablename = 'session_members'
        ) then
            alter publication supabase_realtime add table public.session_members;
        end if;

        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
                and schemaname = 'public'
                and tablename = 'session_events'
        ) then
            alter publication supabase_realtime add table public.session_events;
        end if;
    end if;
end $$;

notify pgrst, 'reload schema';
