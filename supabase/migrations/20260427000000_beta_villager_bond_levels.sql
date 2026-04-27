create or replace function public.villager_bond_level(completed_pair_sessions integer)
returns integer
language sql
immutable
as $$
    select case
        when coalesce(completed_pair_sessions, 0) >= 12 then 5
        when coalesce(completed_pair_sessions, 0) >= 9 then 4
        when coalesce(completed_pair_sessions, 0) >= 6 then 3
        when coalesce(completed_pair_sessions, 0) >= 3 then 2
        when coalesce(completed_pair_sessions, 0) >= 1 then 1
        else 0
    end;
$$;
