alter table if exists public.user_scores
    rename to user_berry_balances;

alter table if exists public.user_berry_balances
    rename column score to berries;

alter table if exists public.user_berry_balances
    rename column current_streak to completion_streak;

alter table if exists public.user_berry_balances
    rename column last_scored_on to last_completed_on;

alter table if exists public.user_berry_balances
    rename column last_scored_at to last_completed_at;

do $$
begin
    if exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_berry_balances'::regclass
            and conname = 'user_scores_pkey'
    ) then
        alter table public.user_berry_balances
            rename constraint user_scores_pkey to user_berry_balances_pkey;
    end if;

    if exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_berry_balances'::regclass
            and conname = 'user_scores_score_nonnegative'
    ) then
        alter table public.user_berry_balances
            rename constraint user_scores_score_nonnegative to user_berry_balances_berries_nonnegative;
    end if;

    if exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_berry_balances'::regclass
            and conname = 'user_scores_current_streak_nonnegative'
    ) then
        alter table public.user_berry_balances
            rename constraint user_scores_current_streak_nonnegative to user_berry_balances_completion_streak_nonnegative;
    end if;

    if exists (
        select 1
        from pg_constraint
        where conrelid = 'public.user_berry_balances'::regclass
            and conname = 'user_scores_streak_requires_score_day'
    ) then
        alter table public.user_berry_balances
            rename constraint user_scores_streak_requires_score_day to user_berry_balances_streak_requires_completion_day;
    end if;
end;
$$;

drop trigger if exists set_public_user_scores_updated_at on public.user_berry_balances;
drop trigger if exists set_public_user_berry_balances_updated_at on public.user_berry_balances;
create trigger set_public_user_berry_balances_updated_at
before update on public.user_berry_balances
for each row
execute function public.set_updated_at();

drop policy if exists "Users can read own score" on public.user_berry_balances;
drop policy if exists "Users can read own berry balance" on public.user_berry_balances;
create policy "Users can read own berry balance"
on public.user_berry_balances
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_berry_balances from anon, authenticated;
grant select on public.user_berry_balances to authenticated;

drop function if exists public.complete_focus_session_with_score(uuid);
drop function if exists public.fetch_user_score();
drop function if exists public.award_user_score_for_completion(uuid, timestamptz);
drop function if exists public.purchase_avatar_hat(integer);
drop function if exists public.collect_pending_berry_rewards();
drop trigger if exists enforce_avatar_hat_score_before_write on public.user_profiles;
drop function if exists public.enforce_avatar_hat_score();
drop function if exists public.avatar_hat_min_score(integer);

create or replace function public.record_user_completion_streak(
    completing_user_id uuid,
    completed_at timestamptz
)
returns void
security definer
set search_path = public, private
language plpgsql
as $$
declare
    completion_timezone text;
    completion_day date;
begin
    select private.user_profiles.user_timezone
    into completion_timezone
    from private.user_profiles
    where private.user_profiles.user_id = completing_user_id;

    if completion_timezone is null or not exists (
        select 1
        from pg_timezone_names
        where name = completion_timezone
    ) then
        completion_timezone := 'UTC';
    end if;

    completion_day := (completed_at at time zone completion_timezone)::date;

    insert into public.user_berry_balances (
        user_id,
        berries,
        completion_streak,
        last_completed_on,
        last_completed_at
    )
    values (
        completing_user_id,
        0,
        1,
        completion_day,
        completed_at
    )
    on conflict (user_id) do update
    set completion_streak = case
            when public.user_berry_balances.last_completed_on is null then 1
            when completion_day < public.user_berry_balances.last_completed_on then public.user_berry_balances.completion_streak
            when completion_day = public.user_berry_balances.last_completed_on then public.user_berry_balances.completion_streak
            when completion_day = public.user_berry_balances.last_completed_on + 1 then public.user_berry_balances.completion_streak + 1
            else 1
        end,
        last_completed_on = case
            when public.user_berry_balances.last_completed_on is null then excluded.last_completed_on
            else greatest(public.user_berry_balances.last_completed_on, excluded.last_completed_on)
        end,
        last_completed_at = case
            when public.user_berry_balances.last_completed_at is null then excluded.last_completed_at
            else greatest(public.user_berry_balances.last_completed_at, excluded.last_completed_at)
        end;
end;
$$;

create or replace function public.fetch_user_berries()
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz
)
security definer
set search_path = public
language sql
stable
as $$
    select
        coalesce(user_berry_balances.berries, 0)::bigint,
        coalesce(user_berry_balances.completion_streak, 0)::integer,
        user_berry_balances.last_completed_on,
        user_berry_balances.last_completed_at
    from (select auth.uid() as user_id) as berry_requester
    left join public.user_berry_balances
        on user_berry_balances.user_id = berry_requester.user_id
    where berry_requester.user_id is not null;
$$;

create or replace function public.purchase_avatar_hat(hat integer)
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    owned_hats integer[]
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    requested_hat integer := $1;
    hat_cost bigint;
    current_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to buy hats.' using errcode = '28000';
    end if;

    hat_cost := public.avatar_hat_berry_cost(requested_hat);

    if hat_cost is null or requested_hat = 0 then
        raise exception 'Invalid avatar hat.' using errcode = '22023';
    end if;

    insert into public.user_berry_balances (user_id)
    values (requester)
    on conflict (user_id) do nothing;

    select *
    into current_balance
    from public.user_berry_balances
    where user_id = requester
    for update;

    if exists (
        select 1
        from public.user_hat_inventory
        where
            user_hat_inventory.user_id = requester
            and user_hat_inventory.hat = requested_hat
    ) then
        raise exception 'You already own that hat.' using errcode = '23505';
    end if;

    if current_balance.berries < hat_cost then
        raise exception 'Not enough berries.' using errcode = '22003';
    end if;

    update public.user_berry_balances
    set berries = public.user_berry_balances.berries - hat_cost
    where public.user_berry_balances.user_id = requester
    returning *
    into current_balance;

    insert into public.user_hat_inventory (user_id, hat)
    values (requester, requested_hat);

    return query
    select
        current_balance.berries,
        current_balance.completion_streak,
        current_balance.last_completed_on,
        current_balance.last_completed_at,
        coalesce(
            array_agg(user_hat_inventory.hat order by user_hat_inventory.hat)
                filter (where user_hat_inventory.hat is not null),
            array[]::integer[]
        )
    from (select requester as user_id) as purchase_owner
    left join public.user_hat_inventory
        on user_hat_inventory.user_id = purchase_owner.user_id
    group by purchase_owner.user_id;
end;
$$;

create or replace function public.collect_pending_berry_rewards()
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    collected_berry_amount bigint,
    collected_reward_count integer,
    collected_black_berries integer,
    collected_white_berries integer,
    collected_red_berries integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    collected_amount bigint := 0;
    reward_count integer := 0;
    black_count integer := 0;
    white_count integer := 0;
    red_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to collect berries.' using errcode = '28000';
    end if;

    with collected_rewards as (
        update public.pending_berry_rewards
        set collected_at = now()
        where user_id = requester
            and collected_at is null
        returning berry_amount, black_berries, white_berries, red_berries
    )
    select
        coalesce(sum(berry_amount), 0)::bigint,
        count(*)::integer,
        coalesce(sum(black_berries), 0)::integer,
        coalesce(sum(white_berries), 0)::integer,
        coalesce(sum(red_berries), 0)::integer
    into collected_amount, reward_count, black_count, white_count, red_count
    from collected_rewards;

    insert into public.user_berry_balances (user_id, berries)
    values (requester, collected_amount)
    on conflict (user_id) do update
    set berries = public.user_berry_balances.berries + excluded.berries;

    return query
    select
        coalesce(user_berry_balances.berries, 0)::bigint,
        coalesce(user_berry_balances.completion_streak, 0)::integer,
        user_berry_balances.last_completed_on,
        user_berry_balances.last_completed_at,
        collected_amount,
        reward_count,
        black_count,
        white_count,
        red_count
    from (select requester as user_id) as berry_requester
    left join public.user_berry_balances
        on user_berry_balances.user_id = berry_requester.user_id;
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
        perform public.record_user_completion_streak(
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
            perform public.record_user_completion_streak(
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

revoke all on function public.record_user_completion_streak(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.fetch_user_berries() from public, anon, authenticated;
revoke all on function public.purchase_avatar_hat(integer) from public, anon, authenticated;
revoke all on function public.collect_pending_berry_rewards() from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;

grant execute on function public.fetch_user_berries() to authenticated;
grant execute on function public.purchase_avatar_hat(integer) to authenticated;
grant execute on function public.collect_pending_berry_rewards() to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;

notify pgrst, 'reload schema';
