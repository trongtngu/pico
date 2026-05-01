create table if not exists public.user_hat_inventory (
    user_id uuid not null references public.user_profiles(user_id) on delete cascade,
    hat integer not null,
    created_at timestamptz not null default now(),
    constraint user_hat_inventory_hat_valid
        check (hat between 1 and 4),
    primary key (user_id, hat)
);

insert into public.user_hat_inventory (user_id, hat)
select
    user_profiles.user_id,
    (user_profiles.avatar_config ->> 'hat')::integer as hat
from public.user_profiles
where
    user_profiles.avatar_config ->> 'version' = '1'
    and user_profiles.avatar_config ->> 'character' = 'character_0'
    and jsonb_typeof(user_profiles.avatar_config -> 'hat') = 'number'
    and user_profiles.avatar_config ->> 'hat' ~ '^[1-4]$'
on conflict (user_id, hat) do nothing;

insert into public.user_hat_inventory (user_id, hat)
select
    user_scores.user_id,
    hat_requirements.hat
from public.user_scores
cross join (
    values
        (1, 3),
        (2, 10),
        (3, 20),
        (4, 30)
) as hat_requirements(hat, required_score)
where user_scores.score >= hat_requirements.required_score
on conflict (user_id, hat) do nothing;

drop trigger if exists enforce_public_user_profiles_avatar_hat_score on public.user_profiles;
drop function if exists public.enforce_avatar_hat_score();

create or replace function public.user_owns_avatar_hat(profile_user_id uuid, selected_hat integer)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select
        selected_hat = 0
        or exists (
            select 1
            from public.user_hat_inventory
            where
                user_hat_inventory.user_id = profile_user_id
                and user_hat_inventory.hat = selected_hat
        );
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
        or new.avatar_config ->> 'hat' !~ '^[0-4]$' then
        return new;
    end if;

    selected_hat := (new.avatar_config ->> 'hat')::integer;

    if not public.user_owns_avatar_hat(new.user_id, selected_hat) then
        raise exception 'You do not own that hat.' using errcode = '42501';
    end if;

    return new;
end;
$$;

drop trigger if exists enforce_public_user_profiles_avatar_hat_ownership on public.user_profiles;
create trigger enforce_public_user_profiles_avatar_hat_ownership
before insert or update of avatar_config on public.user_profiles
for each row
execute function public.enforce_avatar_hat_ownership();

alter table public.user_hat_inventory enable row level security;

drop policy if exists "Users can read own hat inventory" on public.user_hat_inventory;
create policy "Users can read own hat inventory"
on public.user_hat_inventory
for select
to authenticated
using (user_id = auth.uid());

revoke all on public.user_hat_inventory from anon, authenticated;
grant select on public.user_hat_inventory to authenticated;

drop function if exists public.avatar_hat_min_score(integer);

revoke all on function public.user_owns_avatar_hat(uuid, integer) from public, anon, authenticated;
revoke all on function public.enforce_avatar_hat_ownership() from public, anon, authenticated;
