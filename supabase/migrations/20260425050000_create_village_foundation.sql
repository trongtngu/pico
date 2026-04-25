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
for each row
execute function public.set_updated_at();

create trigger set_public_village_residents_updated_at
before update on public.village_residents
for each row
execute function public.set_updated_at();

create trigger set_public_villager_bonds_updated_at
before update on public.villager_bonds
for each row
execute function public.set_updated_at();

create or replace function public.villager_bond_level(completed_pair_sessions integer)
returns integer
language sql
immutable
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

create or replace function public.ensure_user_village()
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
for each row
execute function public.ensure_user_village();

insert into public.villages (owner_id)
select user_id
from public.user_profiles
on conflict (owner_id) do nothing;

create or replace function public.award_villager_completion_pairs(
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
        values (
            user_one,
            user_two,
            1,
            completed_at,
            completed_at
        )
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
        values (
            completing_user_village_id,
            completed_peer_id,
            target_session_id,
            completed_at
        )
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
        values (
            peer_village_id,
            completing_user_id,
            target_session_id,
            completed_at
        )
        on conflict (village_id, resident_user_id) do nothing;
    end loop;
end;
$$;

create or replace function public.complete_focus_session(target_session_id uuid)
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
        and status in ('live', 'completed')
    for update;

    if not found then
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

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.award_villager_completion_pairs(
            target_session_id,
            requester,
            completion_recorded_at
        );
    end if;

    if session_record.status = 'live' and session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    elsif session_record.status = 'live' and session_record.mode = 'multiplayer' and not exists (
        select 1
        from public.session_members
        where session_members.session_id = target_session_id
            and session_members.status = 'joined'
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = target_session_id
                    and session_events.user_id = session_members.user_id
                    and session_events.event_type = 'member_completed'
            )
    ) then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.list_village_residents()
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

alter table public.villages enable row level security;
alter table public.village_residents enable row level security;
alter table public.villager_bonds enable row level security;

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

revoke all on public.villages from anon, authenticated;
revoke all on public.village_residents from anon, authenticated;
revoke all on public.villager_bonds from anon, authenticated;

grant select on public.villages to authenticated;
grant select on public.village_residents to authenticated;
grant select on public.villager_bonds to authenticated;

revoke all on function public.villager_bond_level(integer) from public, anon, authenticated;
revoke all on function public.ensure_user_village() from public, anon, authenticated;
revoke all on function public.award_villager_completion_pairs(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.list_village_residents() from public, anon, authenticated;

grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.list_village_residents() to authenticated;
