alter table private.user_profiles
add column if not exists daily_focus_goal_minutes integer;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'private_user_profiles_daily_focus_goal_minutes_range'
    ) then
        alter table private.user_profiles
        add constraint private_user_profiles_daily_focus_goal_minutes_range
            check (
                daily_focus_goal_minutes is null
                or daily_focus_goal_minutes between 1 and 1440
            );
    end if;
end;
$$;

create or replace function public.fetch_daily_focus_goal()
returns table (
    daily_focus_goal_minutes integer
)
security definer
stable
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to fetch your daily focus goal.' using errcode = '28000';
    end if;

    return query
    select private.user_profiles.daily_focus_goal_minutes
    from private.user_profiles
    where private.user_profiles.user_id = requester;
end;
$$;

create or replace function public.set_daily_focus_goal(goal_minutes integer)
returns table (
    daily_focus_goal_minutes integer
)
security definer
set search_path = public, private
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_goal_minutes integer := goal_minutes;
begin
    if requester is null then
        raise exception 'You must be signed in to update your daily focus goal.' using errcode = '28000';
    end if;

    if normalized_goal_minutes is not null
        and (normalized_goal_minutes < 1 or normalized_goal_minutes > 1440) then
        raise exception 'Daily focus goal must be between 1 and 1440 minutes.' using errcode = '22023';
    end if;

    insert into private.user_profiles (user_id, daily_focus_goal_minutes)
    values (requester, normalized_goal_minutes)
    on conflict (user_id) do update
    set daily_focus_goal_minutes = excluded.daily_focus_goal_minutes;

    return query
    select normalized_goal_minutes;
end;
$$;

revoke all on function public.fetch_daily_focus_goal() from public, anon, authenticated;
revoke all on function public.set_daily_focus_goal(integer) from public, anon, authenticated;

grant execute on function public.fetch_daily_focus_goal() to authenticated;
grant execute on function public.set_daily_focus_goal(integer) to authenticated;
