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
    free_member_limit integer := 4;
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

    if not public.user_has_pico_plus(requester)
        and current_member_count + new_invitee_count > free_member_limit then
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

revoke all on function public.invite_focus_session_members(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.invite_focus_session_members(uuid, uuid[]) to authenticated;

drop function if exists public.pico_plus_multiplayer_member_limit(uuid);
