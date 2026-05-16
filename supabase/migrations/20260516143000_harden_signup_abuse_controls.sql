create or replace function public.is_username_available(target_username text)
returns boolean
language sql
security definer
set search_path = ''
as $$
    select lower(btrim(target_username)) ~ '^[a-z0-9_]{3,24}$'
        and not exists (
            select 1
            from public.user_profiles
            where user_profiles.username = lower(btrim(target_username))
            limit 1
        );
$$;

revoke all on function public.is_username_available(text) from public, anon, authenticated;
grant execute on function public.is_username_available(text) to anon, authenticated;

revoke all on function public.is_email_available(text) from public, anon, authenticated;

drop policy if exists "Anyone can read public profiles" on public.user_profiles;
drop policy if exists "Authenticated users can read public profiles" on public.user_profiles;

create policy "Authenticated users can read public profiles"
on public.user_profiles
for select
to authenticated
using (true);

revoke select on public.user_profiles from anon;
