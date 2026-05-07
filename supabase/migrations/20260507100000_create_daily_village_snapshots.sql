create or replace function public.validate_daily_village_snapshot_owner_profile(
    owner_id uuid,
    profile jsonb
)
returns boolean
language sql
immutable
as $$
    select case
        when owner_id is null then false
        when profile is null or jsonb_typeof(profile) <> 'object' then false
        when (profile ->> 'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
        else
            coalesce(
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

create or replace function public.validate_daily_village_snapshot_visitors(
    owner_id uuid,
    visitors jsonb
)
returns boolean
language sql
immutable
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
                    else
                        coalesce(
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

create or replace function public.validate_daily_village_snapshot_focus_session_ids(
    focus_session_ids uuid[]
)
returns boolean
language sql
immutable
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

create or replace function public.merge_daily_village_snapshot_focus_session_ids(
    existing_ids uuid[],
    incoming_ids uuid[]
)
returns uuid[]
language sql
immutable
as $$
    select coalesce(array_agg(distinct session_id order by session_id), '{}'::uuid[])
    from unnest(coalesce(existing_ids, '{}'::uuid[]) || coalesce(incoming_ids, '{}'::uuid[])) as session_ids(session_id)
    where session_id is not null;
$$;

create or replace function public.merge_daily_village_snapshot_visitors(
    existing_visitors jsonb,
    incoming_visitors jsonb
)
returns jsonb
language sql
immutable
as $$
    with combined_visitors as (
        select
            visitor,
            false as is_incoming,
            ordinal_position
        from jsonb_array_elements(coalesce(existing_visitors, '[]'::jsonb))
            with ordinality as visitor_entries(visitor, ordinal_position)

        union all

        select
            visitor,
            true as is_incoming,
            ordinal_position
        from jsonb_array_elements(coalesce(incoming_visitors, '[]'::jsonb))
            with ordinality as visitor_entries(visitor, ordinal_position)
    ),
    ranked_visitors as (
        select
            visitor,
            row_number() over (
                partition by lower(visitor ->> 'user_id')
                order by
                    (visitor ->> 'completed_pair_sessions')::integer desc,
                    is_incoming desc,
                    ordinal_position desc
            ) as visitor_rank
        from combined_visitors
    )
    select coalesce(
        jsonb_agg(
            visitor
            order by
                lower(visitor ->> 'display_name'),
                lower(visitor ->> 'username'),
                lower(visitor ->> 'user_id')
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
    constraint daily_village_snapshots_pkey
        primary key (owner_id, snapshot_day),
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
for each row
execute function public.set_updated_at();

create or replace function public.validate_daily_village_snapshot_references()
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
for each row
execute function public.validate_daily_village_snapshot_references();

create or replace function public.prevent_daily_village_snapshot_identity_update()
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
for each row
execute function public.prevent_daily_village_snapshot_identity_update();

alter table public.daily_village_snapshots enable row level security;

create policy "Users can read own daily village snapshots"
on public.daily_village_snapshots
for select
to authenticated
using (owner_id = auth.uid());

revoke all on public.daily_village_snapshots from public, anon, authenticated;
grant select on public.daily_village_snapshots to authenticated;

create or replace function public.list_daily_village_snapshots(
    start_day date,
    end_day date
)
returns setof public.daily_village_snapshots
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
    select daily_village_snapshots.*
    from public.daily_village_snapshots
    where owner_id = requester
        and snapshot_day between start_day and end_day
    order by snapshot_day desc;
end;
$$;

create or replace function public.fetch_daily_village_snapshot(snapshot_day date)
returns setof public.daily_village_snapshots
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

    if snapshot_day is null then
        raise exception 'Snapshot day is required.' using errcode = '22023';
    end if;

    return query
    select daily_village_snapshots.*
    from public.daily_village_snapshots
    where owner_id = requester
        and daily_village_snapshots.snapshot_day = $1;
end;
$$;

create or replace function public.upsert_daily_village_snapshot(
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

comment on table public.daily_village_snapshots is
    'Immutable per-user daily village render snapshots keyed by owner and user-local day.';

comment on function public.list_daily_village_snapshots(date, date) is
    'Lists the signed-in user''s daily village snapshots for an inclusive user-local date range.';

comment on function public.fetch_daily_village_snapshot(date) is
    'Fetches one daily village snapshot for the signed-in user and requested user-local date.';

comment on function public.upsert_daily_village_snapshot(uuid, uuid, timestamptz) is
    'Internal writer for daily village snapshots. Computes the owner-local day, captures owner profile/island state, and merges multiplayer visitors.';

revoke all on function public.validate_daily_village_snapshot_owner_profile(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_visitors(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_focus_session_ids(uuid[]) from public, anon, authenticated;
revoke all on function public.merge_daily_village_snapshot_focus_session_ids(uuid[], uuid[]) from public, anon, authenticated;
revoke all on function public.merge_daily_village_snapshot_visitors(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.validate_daily_village_snapshot_references() from public, anon, authenticated;
revoke all on function public.prevent_daily_village_snapshot_identity_update() from public, anon, authenticated;
revoke all on function public.list_daily_village_snapshots(date, date) from public, anon, authenticated;
revoke all on function public.fetch_daily_village_snapshot(date) from public, anon, authenticated;
revoke all on function public.upsert_daily_village_snapshot(uuid, uuid, timestamptz) from public, anon, authenticated;

grant execute on function public.list_daily_village_snapshots(date, date) to authenticated;
grant execute on function public.fetch_daily_village_snapshot(date) to authenticated;

notify pgrst, 'reload schema';
