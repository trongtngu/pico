create or replace function public.is_email_available(target_email text)
returns boolean
language sql
security definer
set search_path = ''
as $$
    select not exists (
        select 1
        from auth.users
        where lower(auth.users.email) = lower(btrim(target_email))
        limit 1
    );
$$;

revoke all on function public.is_email_available(text) from public;
grant execute on function public.is_email_available(text) to anon, authenticated;
