alter table public.user_fish_catches
add column sea_critter_id text;

update public.user_fish_catches
set sea_critter_id = fish_type
where sea_critter_id is null;

alter table public.user_fish_catches
add constraint user_fish_catches_sea_critter_id_fkey
foreign key (sea_critter_id) references public.sea_critters(id);

alter table public.user_fish_catches
alter column sea_critter_id set not null;

create index user_fish_catches_user_sea_critter_idx
on public.user_fish_catches (user_id, sea_critter_id);

create index user_fish_catches_user_unsold_sea_critter_idx
on public.user_fish_catches (user_id, sea_critter_id)
where sold_at is null;

create or replace function public.create_focus_session_fish_catches(
    completing_user_id uuid,
    target_session_id uuid,
    caught_at timestamptz default now()
)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
    catch_time timestamptz := caught_at;
begin
    insert into public.user_fish_catches (
        user_id,
        session_id,
        catch_index,
        fish_type,
        sea_critter_id,
        rarity,
        sell_value,
        caught_at
    )
    select
        completing_user_id,
        target_session_id,
        random_fish_catches.catch_index,
        random_fish_catches.fish_type,
        random_fish_catches.fish_type,
        random_fish_catches.rarity,
        random_fish_catches.sell_value,
        catch_time
    from public.random_fish_catches()
    on conflict (user_id, session_id, catch_index) do nothing;
end;
$$;

revoke all on function public.create_focus_session_fish_catches(uuid, uuid, timestamptz) from public, anon, authenticated;

notify pgrst, 'reload schema';
