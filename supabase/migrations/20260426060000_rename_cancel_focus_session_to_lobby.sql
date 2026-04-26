drop function if exists public.cancel_focus_session(uuid);

create or replace function public.cancel_session_lobby(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to cancel a focus lobby.' using errcode = '28000';
    end if;

    update public.focus_sessions
    set status = 'cancelled',
        ended_at = now()
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
        raise exception 'No cancellable focus lobby was found.' using errcode = 'P0002';
    end if;

    update public.session_members
    set status = 'left'
    where session_id = target_session_id;

    return public.focus_session_payload(target_session_id);
end;
$$;

revoke all on function public.cancel_session_lobby(uuid) from public, anon, authenticated;
grant execute on function public.cancel_session_lobby(uuid) to authenticated;

notify pgrst, 'reload schema';
