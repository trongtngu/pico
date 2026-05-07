drop function if exists public.list_daily_village_snapshots(date, date);
drop function if exists public.fetch_daily_village_snapshot(date);

create or replace function public.list_daily_village_snapshots(
    start_day date,
    end_day date
)
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
        coalesce((
            select sum(focus_sessions.duration_seconds)::integer
            from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
            join public.focus_sessions
                on focus_sessions.id = snapshot_sessions.session_id
        ), 0) as total_focus_seconds,
        coalesce((
            select count(user_fish_catches.id)::integer
            from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
            join public.user_fish_catches
                on user_fish_catches.session_id = snapshot_sessions.session_id
                and user_fish_catches.user_id = snapshots.owner_id
        ), 0) as fish_caught_count,
        snapshots.created_at,
        snapshots.updated_at
    from public.daily_village_snapshots as snapshots
    where snapshots.owner_id = requester
        and snapshots.snapshot_day between start_day and end_day
    order by snapshots.snapshot_day desc;
end;
$$;

create or replace function public.fetch_daily_village_snapshot(requested_snapshot_day date)
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
        coalesce((
            select sum(focus_sessions.duration_seconds)::integer
            from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
            join public.focus_sessions
                on focus_sessions.id = snapshot_sessions.session_id
        ), 0) as total_focus_seconds,
        coalesce((
            select count(user_fish_catches.id)::integer
            from unnest(snapshots.focus_session_ids) as snapshot_sessions(session_id)
            join public.user_fish_catches
                on user_fish_catches.session_id = snapshot_sessions.session_id
                and user_fish_catches.user_id = snapshots.owner_id
        ), 0) as fish_caught_count,
        snapshots.created_at,
        snapshots.updated_at
    from public.daily_village_snapshots as snapshots
    where snapshots.owner_id = requester
        and snapshots.snapshot_day = requested_snapshot_day;
end;
$$;

comment on function public.list_daily_village_snapshots(date, date) is
    'Lists the signed-in user''s daily village snapshots with focus and fish totals for an inclusive user-local date range.';

comment on function public.fetch_daily_village_snapshot(date) is
    'Fetches one daily village snapshot with focus and fish totals for the signed-in user and requested user-local date.';

revoke all on function public.list_daily_village_snapshots(date, date) from public, anon, authenticated;
revoke all on function public.fetch_daily_village_snapshot(date) from public, anon, authenticated;

grant execute on function public.list_daily_village_snapshots(date, date) to authenticated;
grant execute on function public.fetch_daily_village_snapshot(date) to authenticated;

notify pgrst, 'reload schema';
