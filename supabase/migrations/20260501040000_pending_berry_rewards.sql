create table if not exists public.pending_berry_rewards (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    session_id uuid not null references public.focus_sessions(id) on delete cascade,
    berry_amount bigint not null default 3,
    created_at timestamptz not null default now(),
    collected_at timestamptz,
    constraint pending_berry_rewards_amount_positive
        check (berry_amount > 0),
    constraint pending_berry_rewards_user_session_unique
        unique (user_id, session_id)
);

create or replace function public.award_user_score_for_completion(
    completing_user_id uuid,
    completed_at timestamptz
)
returns void
security definer
set search_path = public, private
language plpgsql
as $$
declare
    score_timezone text;
    score_day date;
begin
    select private.user_profiles.user_timezone
    into score_timezone
    from private.user_profiles
    where private.user_profiles.user_id = completing_user_id;

    if score_timezone is null or not exists (
        select 1
        from pg_timezone_names
        where name = score_timezone
    ) then
        score_timezone := 'UTC';
    end if;

    score_day := (completed_at at time zone score_timezone)::date;

    insert into public.user_scores (
        user_id,
        score,
        current_streak,
        last_scored_on,
        last_scored_at
    )
    values (
        completing_user_id,
        0,
        1,
        score_day,
        completed_at
    )
    on conflict (user_id) do update
    set current_streak = case
            when public.user_scores.last_scored_on is null then 1
            when score_day < public.user_scores.last_scored_on then public.user_scores.current_streak
            when score_day = public.user_scores.last_scored_on then public.user_scores.current_streak
            when score_day = public.user_scores.last_scored_on + 1 then public.user_scores.current_streak + 1
            else 1
        end,
        last_scored_on = case
            when public.user_scores.last_scored_on is null then excluded.last_scored_on
            else greatest(public.user_scores.last_scored_on, excluded.last_scored_on)
        end,
        last_scored_at = case
            when public.user_scores.last_scored_at is null then excluded.last_scored_at
            else greatest(public.user_scores.last_scored_at, excluded.last_scored_at)
        end;
end;
$$;

create or replace function public.create_pending_berry_reward(
    completing_user_id uuid,
    target_session_id uuid
)
returns void
security definer
set search_path = public
language sql
as $$
    insert into public.pending_berry_rewards (user_id, session_id, berry_amount)
    values (completing_user_id, target_session_id, 3)
    on conflict (user_id, session_id) do nothing;
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
        and (
            status in ('live', 'completed')
            or (mode = 'multiplayer' and status = 'launched')
        )
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

    if session_record.mode = 'multiplayer' and exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_interrupted'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.award_user_score_for_completion(
            requester,
            completion_recorded_at
        );

        perform public.create_pending_berry_reward(
            requester,
            target_session_id
        );

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
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.collect_pending_berry_rewards()
returns table (
    score bigint,
    current_streak integer,
    last_scored_on date,
    last_scored_at timestamptz,
    collected_berry_amount bigint,
    collected_reward_count integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    collected_amount bigint := 0;
    reward_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to collect berries.' using errcode = '28000';
    end if;

    with collected_rewards as (
        update public.pending_berry_rewards
        set collected_at = now()
        where user_id = requester
            and collected_at is null
        returning berry_amount
    )
    select
        coalesce(sum(berry_amount), 0)::bigint,
        count(*)::integer
    into collected_amount, reward_count
    from collected_rewards;

    insert into public.user_scores (user_id, score)
    values (requester, collected_amount)
    on conflict (user_id) do update
    set score = public.user_scores.score + excluded.score;

    return query
    select
        coalesce(user_scores.score, 0)::bigint,
        coalesce(user_scores.current_streak, 0)::integer,
        user_scores.last_scored_on,
        user_scores.last_scored_at,
        collected_amount,
        reward_count
    from (select requester as user_id) as score_requester
    left join public.user_scores
        on user_scores.user_id = score_requester.user_id;
end;
$$;

create or replace function public.reconcile_open_focus_sessions()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    reconciled_at timestamptz := now();
    stale_lobby_after interval := interval '24 hours';
    session_record record;
    completion_recorded_at timestamptz;
    completed_count integer := 0;
    cancelled_lobby_count integer := 0;
    left_lobby_count integer := 0;
    repaired_cancelled_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to reconcile focus sessions.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));

    update public.session_members
    set status = 'left'
    from public.focus_sessions
    where session_members.session_id = focus_sessions.id
        and session_members.user_id = requester
        and session_members.status in ('invited', 'joined')
        and focus_sessions.status = 'cancelled';

    get diagnostics repaired_cancelled_count = row_count;
    cancelled_lobby_count := cancelled_lobby_count + repaired_cancelled_count;

    for session_record in
        select
            focus_sessions.*,
            session_members.role as member_role
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.status = 'lobby'
            and focus_sessions.updated_at <= reconciled_at - stale_lobby_after
        for update of focus_sessions
    loop
        if session_record.owner_id = requester or session_record.member_role = 'host' then
            update public.focus_sessions
            set status = 'cancelled',
                ended_at = reconciled_at
            where id = session_record.id
                and status = 'lobby';

            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and status in ('invited', 'joined');

            cancelled_lobby_count := cancelled_lobby_count + 1;
        else
            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and user_id = requester
                and status = 'joined';

            left_lobby_count := left_lobby_count + 1;
        end if;
    end loop;

    for session_record in
        select focus_sessions.*
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.planned_end_at <= reconciled_at
            and (
                (
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                )
            )
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = focus_sessions.id
                    and session_events.user_id = requester
                    and session_events.event_type in ('member_completed', 'member_interrupted')
            )
        for update of focus_sessions
    loop
        completion_recorded_at := null;

        insert into public.session_events (session_id, user_id, event_type)
        values (session_record.id, requester, 'member_completed')
        on conflict do nothing
        returning occurred_at into completion_recorded_at;

        if completion_recorded_at is not null then
            perform public.award_user_score_for_completion(
                requester,
                completion_recorded_at
            );

            perform public.create_pending_berry_reward(
                requester,
                session_record.id
            );

            perform public.award_villager_completion_pairs(
                session_record.id,
                requester,
                completion_recorded_at
            );
        end if;

        if session_record.mode = 'solo' then
            update public.focus_sessions
            set status = 'completed',
                ended_at = greatest(reconciled_at, planned_end_at)
            where id = session_record.id
                and status = 'live';
        end if;

        completed_count := completed_count + 1;
    end loop;

    return jsonb_build_object(
        'reconciled_at', reconciled_at,
        'completed_sessions', completed_count,
        'cancelled_lobbies', cancelled_lobby_count,
        'left_lobbies', left_lobby_count
    );
end;
$$;

alter table public.pending_berry_rewards enable row level security;

drop policy if exists "Users can read own pending berry rewards" on public.pending_berry_rewards;
create policy "Users can read own pending berry rewards"
on public.pending_berry_rewards
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.pending_berry_rewards from anon, authenticated;
grant select on public.pending_berry_rewards to authenticated;

revoke all on function public.award_user_score_for_completion(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.create_pending_berry_reward(uuid, uuid) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.collect_pending_berry_rewards() from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;

grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.collect_pending_berry_rewards() to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;

notify pgrst, 'reload schema';
