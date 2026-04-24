-- Auth users are managed by Supabase in auth.users.
-- This baseline creates app-owned user rows plus public/private profile tables.

create schema if not exists private;

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists public.user_profiles cascade;
drop table if exists private.user_profiles cascade;
drop table if exists public.users cascade;

drop function if exists public.handle_new_auth_user();
drop function if exists public.validate_avatar_config(jsonb);
drop function if exists public.set_updated_at();

create or replace function public.validate_avatar_config(config jsonb)
returns boolean
language sql
immutable
as $$
    select case
        when config is null or jsonb_typeof(config) <> 'object' then false
        else
            config ->> 'type' = 'preset'
            and config ->> 'key' in ('avatar_1', 'avatar_2', 'avatar_3', 'avatar_4')
            and (select count(*) from jsonb_object_keys(config)) = 2
    end;
$$;

create table public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    username text not null unique,
    display_name text not null,
    avatar_config jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_profiles_username_format
        check (username ~ '^[a-z0-9_]{3,24}$'),
    constraint user_profiles_display_name_format
        check (
            display_name = btrim(display_name)
            and char_length(display_name) between 1 and 40
        ),
    constraint user_profiles_avatar_config_format
        check (public.validate_avatar_config(avatar_config))
);

create table private.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger set_public_users_updated_at
before update on public.users
for each row
execute function public.set_updated_at();

create trigger set_public_user_profiles_updated_at
before update on public.user_profiles
for each row
execute function public.set_updated_at();

create trigger set_private_user_profiles_updated_at
before update on private.user_profiles
for each row
execute function public.set_updated_at();

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

    insert into public.users (id)
    values (new.id);

    insert into public.user_profiles (user_id, username, display_name, avatar_config)
    values (new.id, profile_username, profile_display_name, profile_avatar_config);

    insert into private.user_profiles (user_id)
    values (new.id);

    return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

alter table public.users enable row level security;
alter table public.user_profiles enable row level security;
alter table private.user_profiles enable row level security;

create policy "Anyone can read public profiles"
on public.user_profiles
for select
to anon, authenticated
using (true);

create policy "Users can insert own public profile"
on public.user_profiles
for insert
to authenticated
with check (user_id = auth.uid());

create policy "Users can update own public profile"
on public.user_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users can read own private profile"
on private.user_profiles
for select
to authenticated
using (user_id = auth.uid());

create policy "Users can update own private profile"
on private.user_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

revoke all on public.users from anon, authenticated;
revoke all on public.user_profiles from anon, authenticated;
revoke all on private.user_profiles from anon, authenticated;

grant usage on schema private to authenticated;
grant select on public.user_profiles to anon, authenticated;
grant insert, update on public.user_profiles to authenticated;
grant select, update on private.user_profiles to authenticated;
