create or replace function public.leave_focus_session(target_session_id uuid)
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
        and status in ('lobby', 'live')
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

    update public.session_members
    set status = 'left'
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined';

    if session_record.status = 'live' then
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
                and status = 'live';
        end if;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

revoke all on function public.leave_focus_session(uuid) from public, anon, authenticated;
grant execute on function public.leave_focus_session(uuid) to authenticated;
