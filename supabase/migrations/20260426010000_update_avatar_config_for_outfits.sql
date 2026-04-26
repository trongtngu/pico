create or replace function public.validate_avatar_config(config jsonb)
returns boolean
language sql
immutable
as $$
    select case
        when config is null or jsonb_typeof(config) <> 'object' then false
        when
            config ->> 'version' = '1'
            and config ->> 'character' = 'character_0'
            and jsonb_typeof(config -> 'hat') = 'number'
            and config ->> 'hat' ~ '^[0-4]$'
            and (select count(*) from jsonb_object_keys(config)) = 3
        then true
        else
            config ->> 'type' = 'preset'
            and config ->> 'key' in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4')
            and (select count(*) from jsonb_object_keys(config)) = 2
    end;
$$;

update public.user_profiles
set avatar_config = jsonb_build_object(
    'version', 1,
    'character', 'character_0',
    'hat', 0
)
where not (
    avatar_config ->> 'version' = '1'
    and avatar_config ->> 'character' = 'character_0'
    and jsonb_typeof(avatar_config -> 'hat') = 'number'
    and avatar_config ->> 'hat' ~ '^[0-4]$'
    and (select count(*) from jsonb_object_keys(avatar_config)) = 3
);
