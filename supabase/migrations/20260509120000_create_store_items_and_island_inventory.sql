create table if not exists public.store_items (
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

drop trigger if exists set_public_store_items_updated_at on public.store_items;
create trigger set_public_store_items_updated_at
before update on public.store_items
for each row
execute function public.set_updated_at();

create table if not exists public.user_store_inventory (
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    store_item_id text not null references public.store_items(id),
    acquired_at timestamptz not null default now(),
    acquisition_source text not null default 'berries',
    primary key (user_id, store_item_id)
);

create index if not exists user_store_inventory_item_idx
on public.user_store_inventory (store_item_id, user_id);

insert into public.store_items (
    id,
    item_type,
    item_key,
    display_name,
    berry_price,
    is_enabled,
    is_limited,
    is_paid_only,
    sort_order,
    metadata
)
values
    ('island:sand', 'island', 'sand', 'Beach Island', 300, true, false, false, 10, '{"island_id": "sand"}'::jsonb),
    ('hat:1', 'hat', '1', 'Bamboo Hat', 5, true, false, false, 101, '{"hat": 1}'::jsonb),
    ('hat:2', 'hat', '2', 'Beanie', 20, true, false, false, 102, '{"hat": 2}'::jsonb),
    ('hat:3', 'hat', '3', 'Bow', 40, true, false, false, 103, '{"hat": 3}'::jsonb),
    ('hat:4', 'hat', '4', 'Helmet', 75, true, false, false, 104, '{"hat": 4}'::jsonb)
on conflict (id) do update
set item_type = excluded.item_type,
    item_key = excluded.item_key,
    display_name = excluded.display_name,
    berry_price = excluded.berry_price,
    is_enabled = excluded.is_enabled,
    is_limited = excluded.is_limited,
    is_paid_only = excluded.is_paid_only,
    sort_order = excluded.sort_order,
    metadata = excluded.metadata;

create or replace function public.user_owns_store_item(
    target_user_id uuid,
    target_item_type text,
    target_item_key text
)
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

create or replace function public.user_owns_avatar_hat(profile_user_id uuid, selected_hat integer)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select
        selected_hat = 0
        or public.user_owns_store_item(
            profile_user_id,
            'hat',
            selected_hat::text
        );
$$;

create or replace function public.user_owns_island(target_user_id uuid, island_id text)
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

alter table public.store_items enable row level security;
alter table public.user_store_inventory enable row level security;

drop policy if exists "Authenticated users can read enabled store items" on public.store_items;
create policy "Authenticated users can read enabled store items"
on public.store_items
for select
to authenticated
using (is_enabled);

drop policy if exists "Users can read own store inventory" on public.user_store_inventory;
create policy "Users can read own store inventory"
on public.user_store_inventory
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.store_items from public, anon, authenticated;
revoke all on public.user_store_inventory from public, anon, authenticated;
grant select on public.store_items to authenticated;
grant select on public.user_store_inventory to authenticated;

drop function if exists public.fetch_store_catalog();
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

drop function if exists public.fetch_user_store_inventory();
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

drop function if exists public.purchase_store_item(text, text);
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
    returning *
    into current_balance;

    insert into public.user_store_inventory (
        user_id,
        store_item_id,
        acquisition_source
    )
    values (
        requester,
        selected_item.id,
        'berries'
    );

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

drop function if exists public.purchase_avatar_hat(integer);
drop function if exists public.avatar_hat_berry_cost(integer);


create or replace function public.create_focus_session(
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

    if duration_seconds is null or duration_seconds < 10 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 seconds and 24 hours.' using errcode = '22023';
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

    insert into public.focus_sessions (
        owner_id,
        mode,
        duration_seconds
    )
    values (
        requester,
        normalized_mode,
        duration_seconds
    )
    returning id into new_session_id;

    insert into public.session_members (
        session_id,
        user_id,
        island_id,
        role,
        status
    )
    values (
        new_session_id,
        requester,
        normalized_island_id,
        'host',
        'joined'
    );

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
end;
$$;

create or replace function public.join_focus_session(target_session_id uuid, island_id text default 'default')
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

revoke all on function public.user_owns_store_item(uuid, text, text) from public, anon, authenticated;
revoke all on function public.user_owns_avatar_hat(uuid, integer) from public, anon, authenticated;
revoke all on function public.user_owns_island(uuid, text) from public, anon, authenticated;
revoke all on function public.fetch_store_catalog() from public, anon, authenticated;
revoke all on function public.fetch_user_store_inventory() from public, anon, authenticated;
revoke all on function public.purchase_store_item(text, text) from public, anon, authenticated;
revoke all on function public.create_focus_session(text, integer, text) from public, anon, authenticated;
revoke all on function public.join_focus_session(uuid, text) from public, anon, authenticated;

grant execute on function public.fetch_store_catalog() to authenticated;
grant execute on function public.fetch_user_store_inventory() to authenticated;
grant execute on function public.purchase_store_item(text, text) to authenticated;
grant execute on function public.create_focus_session(text, integer, text) to authenticated;
grant execute on function public.join_focus_session(uuid, text) to authenticated;

notify pgrst, 'reload schema';
