drop function if exists public.list_daily_focus_activity(date, date);

create or replace function public.list_daily_focus_activity(
    start_day date,
    end_day date
)
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

comment on function public.list_daily_focus_activity(date, date) is
    'Returns one lightweight activity row per requested user-local day for calendar bucket state.';

revoke all on function public.list_daily_focus_activity(date, date) from public, anon, authenticated;
grant execute on function public.list_daily_focus_activity(date, date) to authenticated;

notify pgrst, 'reload schema';
