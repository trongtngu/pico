-- This migration exists because 20260425020000 may already be marked as
-- applied in Supabase. Reapply the focus-session clean cut under a new
-- migration version so db push actually drops old session data and installs
-- the lean multiplayer schema/RPC surface below.

-- Clean cut for the focus-session architecture: discard all existing focus
-- lobby/session/member/event data and recreate the lean schema below. Drop
-- tables first so their RLS policies no longer depend on helper functions.
drop table if exists public.session_events cascade;
drop table if exists public.session_members cascade;
drop table if exists public.focus_sessions cascade;

drop function if exists public.create_solo_focus_session(integer);
drop function if exists public.create_focus_session(text, integer);
drop function if exists public.update_focus_session_config(uuid, integer);
drop function if exists public.invite_focus_session_members(uuid, uuid[]);
drop function if exists public.join_focus_session(uuid);
drop function if exists public.decline_focus_session(uuid);
drop function if exists public.mark_member_ready(uuid);
drop function if exists public.start_focus_session(uuid);
drop function if exists public.record_session_event(uuid, text, jsonb);
drop function if exists public.complete_focus_session(uuid);
drop function if exists public.interrupt_focus_session(uuid);
drop function if exists public.interrupt_focus_session(uuid, text, jsonb);
drop function if exists public.cancel_focus_session(uuid);
drop function if exists public.focus_session_payload(uuid);
drop function if exists public.focus_session_detail_payload(uuid);
drop function if exists public.fetch_focus_session_detail(uuid);
drop function if exists public.list_incoming_focus_session_invites();
drop function if exists public.can_read_focus_session_member(uuid, uuid);
drop function if exists public.is_focus_session_member(uuid);

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
        check (status in ('lobby', 'live', 'interrupted', 'completed', 'cancelled')),
    constraint focus_sessions_duration_seconds
        check (duration_seconds between 60 and 86400),
    constraint focus_sessions_lifecycle_timestamps
        check (
            (status = 'lobby' and started_at is null and planned_end_at is null and ended_at is null)
            or (status = 'live' and started_at is not null and planned_end_at is not null and ended_at is null)
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
        check (
            event_type in (
                'member_joined',
                'session_started',
                'member_interrupted',
                'member_completed'
            )
        )
);

create unique index session_events_member_completed_once
on public.session_events (session_id, user_id)
where event_type = 'member_completed';

create unique index session_events_member_interrupted_once
on public.session_events (session_id, user_id)
where event_type = 'member_interrupted';

create trigger set_public_focus_sessions_updated_at
before update on public.focus_sessions
for each row
execute function public.set_updated_at();

create trigger set_public_session_members_updated_at
before update on public.session_members
for each row
execute function public.set_updated_at();

create or replace function public.is_focus_session_member(target_session_id uuid)
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

create or replace function public.can_read_focus_session_member(target_session_id uuid, target_user_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select public.is_focus_session_member(target_session_id)
        or target_user_id = auth.uid();
$$;

create or replace function public.focus_session_payload(target_session_id uuid)
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

create or replace function public.focus_session_detail_payload(target_session_id uuid)
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

create or replace function public.fetch_focus_session_detail(target_session_id uuid)
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

create or replace function public.list_incoming_focus_session_invites()
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

alter table public.focus_sessions enable row level security;
alter table public.session_members enable row level security;
alter table public.session_events enable row level security;

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

revoke all on public.focus_sessions from anon, authenticated;
revoke all on public.session_members from anon, authenticated;
revoke all on public.session_events from anon, authenticated;

grant select on public.focus_sessions to authenticated;
grant select on public.session_members to authenticated;
grant select on public.session_events to authenticated;

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

create or replace function public.create_focus_session(
    session_mode text default 'solo',
    duration_seconds integer default 1800
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    new_session_id uuid;
    normalized_mode text := lower(btrim(session_mode));
begin
    if requester is null then
        raise exception 'You must be signed in to create a focus session.' using errcode = '28000';
    end if;

    if normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 60 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 60 seconds and 24 hours.' using errcode = '22023';
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
        role,
        status
    )
    values (
        new_session_id,
        requester,
        'host',
        'joined'
    );

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
exception
    when unique_violation then
        raise exception 'You already have an open focus session.' using errcode = '23505';
end;
$$;

create or replace function public.update_focus_session_config(
    target_session_id uuid,
    duration_seconds integer
)
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

    if duration_seconds is null or duration_seconds < 60 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 60 seconds and 24 hours.' using errcode = '22023';
    end if;

    update public.focus_sessions
    set duration_seconds = update_focus_session_config.duration_seconds
    where id = target_session_id
        and owner_id = requester
        and status = 'lobby';

    if not found then
        raise exception 'No configurable focus lobby was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.invite_focus_session_members(
    target_session_id uuid,
    invitee_ids uuid[]
)
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
        and status = 'lobby'
    for update;

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
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
            where (
                friendships.user_one_id = least(requester, invitee)
                and friendships.user_two_id = greatest(requester, invitee)
            )
        ) then
            raise exception 'Only friends can be invited to a focus session.' using errcode = '22023';
        end if;

        insert into public.session_members (
            session_id,
            user_id,
            role,
            status
        )
        values (
            target_session_id,
            invitee,
            'participant',
            'invited'
        )
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

create or replace function public.join_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    joined_now boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to join a focus session.' using errcode = '28000';
    end if;

    update public.session_members
    set status = 'joined'
    where session_id = target_session_id
        and user_id = requester
        and status = 'invited'
        and exists (
            select 1
            from public.focus_sessions
            where focus_sessions.id = target_session_id
                and focus_sessions.status = 'lobby'
        );

    joined_now := found;

    if not joined_now and not exists (
        select 1
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.session_id = target_session_id
            and session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.status = 'lobby'
    ) then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if joined_now then
        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_joined');
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.decline_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to decline a focus session.' using errcode = '28000';
    end if;

    update public.session_members
    set status = 'declined'
    where session_id = target_session_id
        and user_id = requester
        and status = 'invited'
        and exists (
            select 1
            from public.focus_sessions
            where focus_sessions.id = target_session_id
                and focus_sessions.status = 'lobby'
        );

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.start_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    starts_at timestamptz := now();
begin
    if requester is null then
        raise exception 'You must be signed in to start a focus session.' using errcode = '28000';
    end if;

    update public.focus_sessions
    set status = 'live',
        started_at = starts_at,
        planned_end_at = starts_at + make_interval(secs => duration_seconds)
    where id = target_session_id
        and owner_id = requester
        and status = 'lobby';

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    update public.session_members
    set status = 'declined'
    where session_id = target_session_id
        and status = 'invited';

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'session_started');

    return public.focus_session_payload(target_session_id);
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
    on conflict do nothing;

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

create or replace function public.cancel_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to cancel a focus session.' using errcode = '28000';
    end if;

    update public.focus_sessions
    set status = 'cancelled',
        ended_at = now()
    where id = target_session_id
        and owner_id = requester
        and status in ('lobby', 'live');

    if not found then
        raise exception 'No cancellable focus session was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.interrupt_focus_session(target_session_id uuid)
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
        and status in ('live', 'interrupted')
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
                and status in ('joined', 'left')
        ) then
            raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
        end if;

        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester;
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_interrupted')
    on conflict do nothing;

    return public.focus_session_payload(target_session_id);
end;
$$;

revoke all on function public.is_focus_session_member(uuid) from public, anon, authenticated;
revoke all on function public.can_read_focus_session_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.focus_session_payload(uuid) from public, anon, authenticated;
revoke all on function public.focus_session_detail_payload(uuid) from public, anon, authenticated;
revoke all on function public.fetch_focus_session_detail(uuid) from public, anon, authenticated;
revoke all on function public.list_incoming_focus_session_invites() from public, anon, authenticated;
revoke all on function public.create_focus_session(text, integer) from public, anon, authenticated;
revoke all on function public.update_focus_session_config(uuid, integer) from public, anon, authenticated;
revoke all on function public.invite_focus_session_members(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.join_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.decline_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.start_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.cancel_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.interrupt_focus_session(uuid) from public, anon, authenticated;

grant execute on function public.is_focus_session_member(uuid) to authenticated;
grant execute on function public.can_read_focus_session_member(uuid, uuid) to authenticated;
grant execute on function public.fetch_focus_session_detail(uuid) to authenticated;
grant execute on function public.list_incoming_focus_session_invites() to authenticated;
grant execute on function public.create_focus_session(text, integer) to authenticated;
grant execute on function public.update_focus_session_config(uuid, integer) to authenticated;
grant execute on function public.invite_focus_session_members(uuid, uuid[]) to authenticated;
grant execute on function public.join_focus_session(uuid) to authenticated;
grant execute on function public.decline_focus_session(uuid) to authenticated;
grant execute on function public.start_focus_session(uuid) to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.cancel_focus_session(uuid) to authenticated;
grant execute on function public.interrupt_focus_session(uuid) to authenticated;
