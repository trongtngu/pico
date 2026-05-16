create table if not exists public.user_plus_entitlements (
    user_id uuid primary key references public.user_profiles(user_id) on delete cascade,
    entitlement_key text not null default 'pico_plus',
    status text not null default 'inactive',
    provider text,
    current_period_end timestamptz,
    updated_at timestamptz not null default now(),
    constraint user_plus_entitlements_key_check
        check (entitlement_key = 'pico_plus'),
    constraint user_plus_entitlements_status_check
        check (status in ('inactive', 'active', 'trialing', 'past_due', 'canceled', 'expired', 'refunded'))
);

create trigger set_public_user_plus_entitlements_updated_at
before update on public.user_plus_entitlements
for each row
execute function public.set_updated_at();

alter table public.user_plus_entitlements enable row level security;

create policy "Users can read own plus entitlement"
on public.user_plus_entitlements
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_plus_entitlements from public, anon, authenticated;
grant select on public.user_plus_entitlements to authenticated;

create or replace function public.user_has_pico_plus(target_user_id uuid)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select exists (
        select 1
        from public.user_plus_entitlements
        where user_plus_entitlements.user_id = target_user_id
            and user_plus_entitlements.entitlement_key = 'pico_plus'
            and user_plus_entitlements.status in ('active', 'trialing')
            and (
                user_plus_entitlements.current_period_end is null
                or user_plus_entitlements.current_period_end > now()
            )
    );
$$;

create or replace function public.pico_plus_multiplayer_member_limit(target_user_id uuid)
returns integer
security definer
stable
set search_path = public
language sql
as $$
    select case
        when public.user_has_pico_plus(target_user_id) then 8
        else 4
    end;
$$;

create or replace function public.fetch_pico_plus_entitlement()
returns table (
    is_active boolean,
    status text,
    provider text,
    current_period_end timestamptz
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
        raise exception 'You must be signed in to fetch Pico Plus entitlement.' using errcode = '28000';
    end if;

    return query
    select
        public.user_has_pico_plus(requester) as is_active,
        entitlements.status,
        entitlements.provider,
        entitlements.current_period_end
    from (select 1) as fallback
    left join public.user_plus_entitlements as entitlements
        on entitlements.user_id = requester
        and entitlements.entitlement_key = 'pico_plus';
end;
$$;

create or replace function public.invite_focus_session_members(target_session_id uuid, invitee_ids uuid[])
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    invitee uuid;
    session_record public.focus_sessions%rowtype;
    requested_invitee_ids uuid[] := array(
        select distinct requested.invitee_id
        from unnest(coalesce(invitee_ids, array[]::uuid[])) as requested(invitee_id)
        where requested.invitee_id is not null
    );
    current_member_count integer;
    new_invitee_count integer;
    member_limit integer;
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

    foreach invitee in array requested_invitee_ids
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
    end loop;

    select count(*)::integer
    into current_member_count
    from public.session_members
    where session_members.session_id = target_session_id
        and session_members.status in ('joined', 'invited');

    select count(*)::integer
    into new_invitee_count
    from unnest(requested_invitee_ids) as requested(invitee_id)
    where not exists (
        select 1
        from public.session_members
        where session_members.session_id = target_session_id
            and session_members.user_id = requested.invitee_id
            and session_members.status in ('joined', 'invited')
    );

    member_limit := public.pico_plus_multiplayer_member_limit(requester);

    if current_member_count + new_invitee_count > member_limit then
        if public.user_has_pico_plus(requester) then
            raise exception 'This focus group is already at the Pico Plus member limit.' using errcode = '22023';
        end if;

        raise exception 'Pico Plus is required for focus groups with more than 4 members.' using errcode = '42501';
    end if;

    foreach invitee in array requested_invitee_ids
    loop
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

revoke all on function public.user_has_pico_plus(uuid) from public, anon, authenticated;
revoke all on function public.pico_plus_multiplayer_member_limit(uuid) from public, anon, authenticated;
revoke all on function public.fetch_pico_plus_entitlement() from public, anon, authenticated;
revoke all on function public.invite_focus_session_members(uuid, uuid[]) from public, anon, authenticated;

grant execute on function public.fetch_pico_plus_entitlement() to authenticated;
grant execute on function public.invite_focus_session_members(uuid, uuid[]) to authenticated;
