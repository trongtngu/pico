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
            and config ->> 'hat' ~ '^[0-5]$'
            and (select count(*) from jsonb_object_keys(config)) = 3
        then true
        else
            config ->> 'type' = 'preset'
            and config ->> 'key' in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4')
            and (select count(*) from jsonb_object_keys(config)) = 2
    end;
$$;

create or replace function public.enforce_avatar_hat_ownership()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
    selected_hat integer;
begin
    if new.avatar_config is null or jsonb_typeof(new.avatar_config) <> 'object' then
        return new;
    end if;

    if not (new.avatar_config ? 'hat') then
        return new;
    end if;

    if jsonb_typeof(new.avatar_config -> 'hat') is distinct from 'number'
        or new.avatar_config ->> 'hat' !~ '^[0-5]$' then
        return new;
    end if;

    selected_hat := (new.avatar_config ->> 'hat')::integer;

    if not public.user_owns_avatar_hat(new.user_id, selected_hat) then
        raise exception 'You do not own that hat.' using errcode = '42501';
    end if;

    return new;
end;
$$;

revoke all on function public.enforce_avatar_hat_ownership() from public, anon, authenticated;
