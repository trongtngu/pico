drop function if exists public.fetch_daily_village_snapshot(date);

create function public.fetch_daily_village_snapshot(requested_snapshot_day date)
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
    fish_counts jsonb,
    total_focused_seconds integer,
    solo_focus_sessions integer,
    group_focus_sessions integer,
    total_focus_sessions integer,
    sessions_interrupted integer,
    created_at timestamptz,
    updated_at timestamptz
)
security definer
stable
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    snapshot_timezone text;
    requester_profile jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to fetch a daily village snapshot.' using errcode = '28000';
    end if;

    if requested_snapshot_day is null then
        raise exception 'Snapshot day is required.' using errcode = '22023';
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

    select jsonb_build_object(
        'user_id', user_profiles.user_id,
        'username', user_profiles.username,
        'display_name', user_profiles.display_name,
        'avatar_config', user_profiles.avatar_config
    )
    into requester_profile
    from public.user_profiles
    where user_profiles.user_id = requester;

    if requester_profile is null then
        raise exception 'No public profile was found for user %.', requester using errcode = 'P0002';
    end if;

    return query
    with focus_metric_rows as (
        select
            focus_sessions.id,
            focus_sessions.mode,
            session_members.island_id,
            greatest(
                0,
                least(
                    focus_sessions.duration_seconds,
                    extract(epoch from (focus_sessions.ended_at - focus_sessions.started_at))::integer
                )
            ) as elapsed_seconds,
            session_members.failed_at is not null
                and session_members.failure_reason in ('interrupted', 'left_multiplayer') as was_interrupted_by_user
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.user_id = requester
            and session_members.committed_at is not null
            and focus_sessions.started_at is not null
            and focus_sessions.ended_at is not null
            and (focus_sessions.ended_at at time zone snapshot_timezone)::date = requested_snapshot_day
    ),
    focus_metrics as (
        select
            coalesce(sum(focus_metric_rows.elapsed_seconds), 0)::integer as total_focused_seconds,
            count(*) filter (where focus_metric_rows.mode = 'solo')::integer as solo_focus_sessions,
            count(*) filter (where focus_metric_rows.mode = 'multiplayer')::integer as group_focus_sessions,
            count(*)::integer as total_focus_sessions,
            count(*) filter (where focus_metric_rows.was_interrupted_by_user)::integer as sessions_interrupted,
            (array_agg(focus_metric_rows.island_id order by focus_metric_rows.id))[1] as fallback_island_id
        from focus_metric_rows
    ),
    selected_snapshot as (
        select snapshots.*
        from public.daily_village_snapshots as snapshots
        where snapshots.owner_id = requester
            and snapshots.snapshot_day = requested_snapshot_day
    )
    select
        requester as owner_id,
        requested_snapshot_day as snapshot_day,
        snapshot_timezone as user_timezone,
        coalesce(selected_snapshot.island_id, focus_metrics.fallback_island_id, 'default') as island_id,
        coalesce(selected_snapshot.owner_profile, requester_profile) as owner_profile,
        coalesce(selected_snapshot.visitors, '[]'::jsonb) as visitors,
        coalesce(selected_snapshot.focus_session_ids, array[]::uuid[]) as focus_session_ids,
        coalesce(focus_totals.total_focus_seconds, 0) as total_focus_seconds,
        coalesce(fish_totals.fish_caught_count, 0) as fish_caught_count,
        coalesce(fish_totals.fish_counts, '[]'::jsonb) as fish_counts,
        focus_metrics.total_focused_seconds,
        focus_metrics.solo_focus_sessions,
        focus_metrics.group_focus_sessions,
        focus_metrics.total_focus_sessions,
        focus_metrics.sessions_interrupted,
        coalesce(selected_snapshot.created_at, now()) as created_at,
        coalesce(selected_snapshot.updated_at, now()) as updated_at
    from focus_metrics
    left join selected_snapshot on true
    left join lateral (
        select sum(focus_sessions.duration_seconds)::integer as total_focus_seconds
        from unnest(coalesce(selected_snapshot.focus_session_ids, array[]::uuid[])) as snapshot_sessions(session_id)
        join public.focus_sessions
            on focus_sessions.id = snapshot_sessions.session_id
    ) as focus_totals on true
    left join lateral (
        select
            coalesce(sum(fish_groups.catch_count), 0)::integer as fish_caught_count,
            coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'sea_critter_id', fish_groups.sea_critter_id,
                        'display_name', fish_groups.display_name,
                        'rarity', fish_groups.rarity,
                        'sell_value', fish_groups.sell_value,
                        'asset_name', fish_groups.asset_name,
                        'sort_order', fish_groups.sort_order,
                        'count', fish_groups.catch_count
                    )
                    order by fish_groups.sort_order, fish_groups.sea_critter_id
                ),
                '[]'::jsonb
            ) as fish_counts
        from (
            select
                sea_critters.id as sea_critter_id,
                sea_critters.display_name,
                sea_critters.rarity,
                sea_critters.sell_value::integer as sell_value,
                sea_critters.asset_name,
                sea_critters.sort_order,
                count(user_fish_catches.id)::integer as catch_count
            from unnest(coalesce(selected_snapshot.focus_session_ids, array[]::uuid[])) as snapshot_sessions(session_id)
            join public.user_fish_catches
                on user_fish_catches.session_id = snapshot_sessions.session_id
                and user_fish_catches.user_id = requester
            join public.sea_critters
                on sea_critters.id = user_fish_catches.sea_critter_id
            group by
                sea_critters.id,
                sea_critters.display_name,
                sea_critters.rarity,
                sea_critters.sell_value,
                sea_critters.asset_name,
                sea_critters.sort_order
        ) as fish_groups
    ) as fish_totals on true
    where selected_snapshot.owner_id is not null
        or focus_metrics.total_focus_sessions > 0;
end;
$$;

create or replace function public.list_daily_focus_activity(start_day date, end_day date)
returns table (
    snapshot_day date,
    has_focus boolean
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
        ) or exists (
            select 1
            from public.session_members
            join public.focus_sessions
                on focus_sessions.id = session_members.session_id
            where session_members.user_id = requester
                and session_members.committed_at is not null
                and focus_sessions.started_at is not null
                and focus_sessions.ended_at is not null
                and (focus_sessions.ended_at at time zone snapshot_timezone)::date = requested_days.snapshot_day
        ) as has_focus
    from requested_days
    order by requested_days.snapshot_day asc;
end;
$$;

revoke all on function public.fetch_daily_village_snapshot(date) from public, anon, authenticated;
revoke all on function public.list_daily_focus_activity(date, date) from public, anon, authenticated;

grant execute on function public.fetch_daily_village_snapshot(date) to authenticated;
grant execute on function public.list_daily_focus_activity(date, date) to authenticated;
