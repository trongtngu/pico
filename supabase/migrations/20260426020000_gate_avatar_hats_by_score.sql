create or replace function public.avatar_hat_min_score(hat integer)
returns bigint
language sql
immutable
set search_path = public
as $$
    select case hat
        when 0 then 0
        when 1 then 10
        when 2 then 20
        when 3 then 30
        when 4 then 40
        else null
    end;
$$;

update public.user_profiles
set avatar_config = jsonb_set(avatar_config, '{hat}', '0'::jsonb)
where
    avatar_config ->> 'version' = '1'
    and avatar_config ->> 'character' = 'character_0'
    and jsonb_typeof(avatar_config -> 'hat') = 'number'
    and avatar_config ->> 'hat' ~ '^[0-4]$'
    and coalesce((
        select user_scores.score
        from public.user_scores
        where user_scores.user_id = user_profiles.user_id
    ), 0) < public.avatar_hat_min_score((avatar_config ->> 'hat')::integer);

create or replace function public.enforce_avatar_hat_score()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
    selected_hat integer;
    required_score bigint;
    profile_score bigint;
begin
    if new.avatar_config is null or jsonb_typeof(new.avatar_config) <> 'object' then
        return new;
    end if;

    if not (new.avatar_config ? 'hat') then
        return new;
    end if;

    if jsonb_typeof(new.avatar_config -> 'hat') is distinct from 'number'
        or new.avatar_config ->> 'hat' !~ '^[0-4]$' then
        return new;
    end if;

    selected_hat := (new.avatar_config ->> 'hat')::integer;
    required_score := public.avatar_hat_min_score(selected_hat);

    if required_score is null then
        raise exception 'Invalid avatar hat.' using errcode = '22023';
    end if;

    select coalesce(user_scores.score, 0)
    into profile_score
    from (select new.user_id as user_id) as profile_owner
    left join public.user_scores
        on user_scores.user_id = profile_owner.user_id;

    if coalesce(profile_score, 0) < required_score then
        raise exception 'You need % points to use that hat.', required_score using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists enforce_public_user_profiles_avatar_hat_score on public.user_profiles;
create trigger enforce_public_user_profiles_avatar_hat_score
before insert or update of avatar_config on public.user_profiles
for each row
execute function public.enforce_avatar_hat_score();

revoke all on function public.avatar_hat_min_score(integer) from public, anon, authenticated;
revoke all on function public.enforce_avatar_hat_score() from public, anon, authenticated;
