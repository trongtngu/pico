create or replace function public.handle_new_auth_user()
returns trigger
security definer
set search_path = public, private
language plpgsql
as $$
declare
    fallback_username text := 'pico_' || substring(replace(new.id::text, '-', '') from 1 for 19);
    email_prefix text := split_part(coalesce(new.email, ''), '@', 1);
    profile_username text := coalesce(
        nullif(lower(btrim(new.raw_user_meta_data ->> 'username')), ''),
        fallback_username
    );
    profile_display_name text := coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
        nullif(btrim(email_prefix), ''),
        'Pico'
    );
    profile_avatar_config jsonb := coalesce(
        new.raw_user_meta_data -> 'avatar_config',
        jsonb_build_object(
            'version', 1,
            'character', 'character_0',
            'hat', 0
        )
    );
    profile_timezone text := coalesce(
        nullif(btrim(new.raw_user_meta_data ->> 'time_zone'), ''),
        nullif(btrim(new.raw_user_meta_data ->> 'timezone'), ''),
        'UTC'
    );
begin
    profile_display_name := left(profile_display_name, 40);

    if profile_username !~ '^[a-z0-9_]{3,24}$' then
        profile_username := fallback_username;
    end if;

    if profile_display_name is null or char_length(profile_display_name) not between 1 and 40 then
        profile_display_name := 'Pico';
    end if;

    if profile_avatar_config is null or not public.validate_avatar_config(profile_avatar_config) then
        profile_avatar_config := jsonb_build_object(
            'version', 1,
            'character', 'character_0',
            'hat', 0
        );
    end if;

    if not exists (
        select 1
        from pg_timezone_names
        where name = profile_timezone
    ) then
        profile_timezone := 'UTC';
    end if;

    insert into public.users (id)
    values (new.id)
    on conflict (id) do nothing;

    insert into public.user_profiles (user_id, username, display_name, avatar_config)
    values (new.id, profile_username, profile_display_name, profile_avatar_config)
    on conflict (user_id) do nothing;

    insert into private.user_profiles (user_id, user_timezone)
    values (new.id, profile_timezone)
    on conflict (user_id) do nothing;

    return new;
end;
$$;
