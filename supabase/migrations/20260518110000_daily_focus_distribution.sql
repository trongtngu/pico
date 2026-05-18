create or replace function public.fetch_daily_focus_distribution(requested_snapshot_day date)
returns table (
    snapshot_day date,
    bucket_hour integer,
    focused_seconds integer,
    total_focused_seconds integer,
    solo_focus_sessions integer,
    group_focus_sessions integer,
    total_focus_sessions integer,
    sessions_interrupted integer
)
security definer
stable
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    snapshot_timezone text;
begin
    if requester is null then
        raise exception 'You must be signed in to fetch daily focus distribution.' using errcode = '28000';
    end if;

    if requested_snapshot_day is null then
        raise exception 'Snapshot day is required.' using errcode = '22023';
    end if;

    if not public.user_has_pico_plus(requester) then
        raise exception 'Pico Plus is required to fetch daily focus distribution.' using errcode = '42501';
    end if;

    select private.user_profiles.user_timezone
    into snapshot_timezone
    from private.user_profiles
    where private.user_profiles.user_id = requester;

    if snapshot_timezone is null or not exists (
        select 1
        from pg_timezone_names
        where name = snapshot_timezone
    ) then
        snapshot_timezone := 'UTC';
    end if;

    return query
    with hour_buckets as (
        select
            hours.bucket_hour,
            requested_snapshot_day::timestamp
                + (hours.bucket_hour * interval '1 hour') as bucket_start,
            requested_snapshot_day::timestamp
                + ((hours.bucket_hour + 1) * interval '1 hour') as bucket_end
        from generate_series(0, 23) as hours(bucket_hour)
    ),
    focus_rows as (
        select
            focus_sessions.id,
            focus_sessions.mode,
            greatest(
                focus_sessions.started_at at time zone snapshot_timezone,
                requested_snapshot_day::timestamp
            ) as focused_start,
            least(
                least(
                    focus_sessions.ended_at,
                    focus_sessions.started_at + make_interval(secs => focus_sessions.duration_seconds)
                ) at time zone snapshot_timezone,
                (requested_snapshot_day + 1)::timestamp
            ) as focused_end,
            session_members.failed_at is not null
                and session_members.failure_reason in ('interrupted', 'left_multiplayer') as was_interrupted_by_user
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.user_id = requester
            and session_members.committed_at is not null
            and (
                session_members.completed_at is not null
                or session_members.failed_at is not null
            )
            and focus_sessions.started_at is not null
            and focus_sessions.ended_at is not null
            and least(
                focus_sessions.ended_at,
                focus_sessions.started_at + make_interval(secs => focus_sessions.duration_seconds)
            ) > focus_sessions.started_at
            and (focus_sessions.started_at at time zone snapshot_timezone) < (requested_snapshot_day + 1)::timestamp
            and (
                least(
                    focus_sessions.ended_at,
                    focus_sessions.started_at + make_interval(secs => focus_sessions.duration_seconds)
                ) at time zone snapshot_timezone
            ) > requested_snapshot_day::timestamp
    ),
    valid_focus_rows as (
        select *
        from focus_rows
        where focused_end > focused_start
    ),
    focus_metrics as (
        select
            coalesce(sum(extract(epoch from (focused_end - focused_start))), 0)::integer as total_focused_seconds,
            count(*) filter (where mode = 'solo')::integer as solo_focus_sessions,
            count(*) filter (where mode = 'multiplayer')::integer as group_focus_sessions,
            count(*)::integer as total_focus_sessions,
            count(*) filter (where was_interrupted_by_user)::integer as sessions_interrupted
        from valid_focus_rows
    ),
    bucket_totals as (
        select
            hour_buckets.bucket_hour,
            coalesce(
                sum(
                    case
                        when valid_focus_rows.id is null then 0
                        else greatest(
                            0,
                            extract(
                                epoch from (
                                    least(valid_focus_rows.focused_end, hour_buckets.bucket_end)
                                    - greatest(valid_focus_rows.focused_start, hour_buckets.bucket_start)
                                )
                            )
                        )
                    end
                ),
                0
            )::integer as focused_seconds
        from hour_buckets
        left join valid_focus_rows
            on valid_focus_rows.focused_start < hour_buckets.bucket_end
            and valid_focus_rows.focused_end > hour_buckets.bucket_start
        group by hour_buckets.bucket_hour
    )
    select
        requested_snapshot_day as snapshot_day,
        bucket_totals.bucket_hour,
        bucket_totals.focused_seconds,
        focus_metrics.total_focused_seconds,
        focus_metrics.solo_focus_sessions,
        focus_metrics.group_focus_sessions,
        focus_metrics.total_focus_sessions,
        focus_metrics.sessions_interrupted
    from bucket_totals
    cross join focus_metrics
    order by bucket_totals.bucket_hour asc;
end;
$$;

revoke all on function public.fetch_daily_focus_distribution(date) from public, anon, authenticated;
grant execute on function public.fetch_daily_focus_distribution(date) to authenticated;
