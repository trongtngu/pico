alter table private.user_profiles
add column if not exists user_timezone text not null default 'UTC';

alter table private.user_profiles
drop constraint if exists private_user_profiles_user_timezone_not_blank;

alter table private.user_profiles
add constraint private_user_profiles_user_timezone_not_blank
    check (length(btrim(user_timezone)) > 0);

create table if not exists public.user_scores (
    user_id uuid primary key references public.user_profiles(user_id) on delete cascade,
    score bigint not null default 0,
    current_streak integer not null default 0,
    last_scored_on date,
    last_scored_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_scores_score_nonnegative
        check (score >= 0),
    constraint user_scores_current_streak_nonnegative
        check (current_streak >= 0),
    constraint user_scores_streak_requires_score_day
        check (
            (current_streak = 0 and last_scored_on is null and last_scored_at is null)
            or (current_streak > 0 and last_scored_on is not null and last_scored_at is not null)
        )
);

drop trigger if exists set_public_user_scores_updated_at on public.user_scores;
create trigger set_public_user_scores_updated_at
before update on public.user_scores
for each row
execute function public.set_updated_at();

create or replace function public.reject_session_events_mutation()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    raise exception 'session_events is append-only.' using errcode = '2F000';
end;
$$;

drop trigger if exists reject_public_session_events_update on public.session_events;
create trigger reject_public_session_events_update
before update on public.session_events
for each row
execute function public.reject_session_events_mutation();

drop trigger if exists reject_public_session_events_delete on public.session_events;
create trigger reject_public_session_events_delete
before delete on public.session_events
for each row
execute function public.reject_session_events_mutation();

create or replace function public.handle_new_auth_user()
returns trigger
security definer
set search_path = public, private
language plpgsql
as $$
declare
    profile_username text := lower(btrim(new.raw_user_meta_data ->> 'username'));
    profile_display_name text := btrim(new.raw_user_meta_data ->> 'display_name');
    profile_avatar_config jsonb := new.raw_user_meta_data -> 'avatar_config';
    profile_timezone text := coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'time_zone'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'timezone'), ''),
        'UTC'
    );
begin
    if profile_username is null or profile_username !~ '^[a-z0-9_]{3,24}$' then
        raise exception 'Invalid username' using errcode = '22023';
    end if;

    if profile_display_name is null or char_length(profile_display_name) not between 1 and 40 then
        raise exception 'Invalid display name' using errcode = '22023';
    end if;

    if profile_avatar_config is null or not public.validate_avatar_config(profile_avatar_config) then
        raise exception 'Invalid avatar config' using errcode = '22023';
    end if;

    if not exists (
        select 1
        from pg_timezone_names
        where name = profile_timezone
    ) then
        profile_timezone := 'UTC';
    end if;

    insert into public.users (id)
    values (new.id);

    insert into public.user_profiles (user_id, username, display_name, avatar_config)
    values (new.id, profile_username, profile_display_name, profile_avatar_config);

    insert into private.user_profiles (user_id, user_timezone)
    values (new.id, profile_timezone);

    return new;
end;
$$;

create or replace function public.set_user_timezone(time_zone text)
returns text
security definer
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_time_zone text := nullif(btrim(time_zone), '');
begin
    if requester is null then
        raise exception 'You must be signed in to update your timezone.' using errcode = '28000';
    end if;

    if normalized_time_zone is null or not exists (
        select 1
        from pg_timezone_names
        where name = normalized_time_zone
    ) then
        raise exception 'Invalid timezone.' using errcode = '22023';
    end if;

    insert into private.user_profiles (user_id, user_timezone)
    values (requester, normalized_time_zone)
    on conflict (user_id) do update
    set user_timezone = excluded.user_timezone;

    return normalized_time_zone;
end;
$$;

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
        1,
        1,
        score_day,
        completed_at
    )
    on conflict (user_id) do update
    set score = public.user_scores.score + 1,
        current_streak = case
            when score_day < public.user_scores.last_scored_on then public.user_scores.current_streak
            when score_day = public.user_scores.last_scored_on then public.user_scores.current_streak
            when score_day = public.user_scores.last_scored_on + 1 then public.user_scores.current_streak + 1
            else 1
        end,
        last_scored_on = greatest(public.user_scores.last_scored_on, excluded.last_scored_on),
        last_scored_at = greatest(public.user_scores.last_scored_at, excluded.last_scored_at);
end;
$$;

delete from public.user_scores;

do $$
declare
    completion_record record;
begin
    for completion_record in
        select session_events.user_id, session_events.occurred_at
        from public.session_events
        where session_events.event_type = 'member_completed'
        order by session_events.occurred_at, session_events.id
    loop
        perform public.award_user_score_for_completion(
            completion_record.user_id,
            completion_record.occurred_at
        );
    end loop;
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
        and status in ('live', 'completed')
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

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.award_user_score_for_completion(
            requester,
            completion_recorded_at
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
    elsif session_record.status = 'live' and session_record.mode = 'multiplayer' and not exists (
        select 1
        from public.session_members
        where session_members.session_id = target_session_id
            and session_members.status = 'joined'
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = target_session_id
                    and session_events.user_id = session_members.user_id
                    and session_events.event_type = 'member_completed'
            )
    ) then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.interrupt_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to interrupt a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and status in ('live', 'interrupted')
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'solo' and session_record.owner_id <> requester then
        raise exception 'Only the host can interrupt a solo focus session.' using errcode = '42501';
    end if;

    if session_record.status = 'interrupted' then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'interrupted',
            ended_at = now()
        where id = target_session_id;
    else
        if not exists (
            select 1
            from public.session_members
            where session_id = target_session_id
                and user_id = requester
                and status = 'joined'
        ) then
            raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
        end if;

        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined';
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_interrupted')
    on conflict do nothing;

    if session_record.mode = 'multiplayer' and not exists (
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

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.fetch_user_score()
returns table (
    score bigint,
    current_streak integer,
    last_scored_on date,
    last_scored_at timestamptz
)
security definer
set search_path = public
language plpgsql
stable
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to view your score.' using errcode = '28000';
    end if;

    return query
    select
        coalesce(user_scores.score, 0)::bigint,
        coalesce(user_scores.current_streak, 0)::integer,
        user_scores.last_scored_on,
        user_scores.last_scored_at
    from (select requester as user_id) as score_requester
    left join public.user_scores
        on user_scores.user_id = score_requester.user_id;
end;
$$;

alter table public.user_scores enable row level security;

drop policy if exists "Users can read own score" on public.user_scores;
create policy "Users can read own score"
on public.user_scores
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_scores from anon, authenticated;
grant select on public.user_scores to authenticated;

revoke all on function public.reject_session_events_mutation() from public, anon, authenticated;
revoke all on function public.set_user_timezone(text) from public, anon, authenticated;
revoke all on function public.award_user_score_for_completion(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.interrupt_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.fetch_user_score() from public, anon, authenticated;

grant execute on function public.set_user_timezone(text) to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.interrupt_focus_session(uuid) to authenticated;
grant execute on function public.fetch_user_score() to authenticated;
