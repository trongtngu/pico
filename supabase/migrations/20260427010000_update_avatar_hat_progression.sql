create or replace function public.avatar_hat_min_score(hat integer)
returns bigint
language sql
immutable
set search_path = public
as $$
    select case hat
        when 0 then 0
        when 1 then 3
        when 2 then 10
        when 3 then 20
        when 4 then 30
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

revoke all on function public.avatar_hat_min_score(integer) from public, anon, authenticated;
