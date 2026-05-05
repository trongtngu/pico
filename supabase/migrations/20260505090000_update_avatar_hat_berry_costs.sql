create or replace function public.avatar_hat_berry_cost(hat integer)
returns bigint
language sql
immutable
set search_path = public
as $$
    select case hat
        when 0 then 0
        when 1 then 5
        when 2 then 20
        when 3 then 40
        when 4 then 75
        else null
    end;
$$;

revoke all on function public.avatar_hat_berry_cost(integer) from public, anon, authenticated;
