create table public.sea_critters (
    id text primary key,
    display_name text not null,
    rarity text not null,
    sell_value bigint not null,
    asset_name text not null,
    sort_order integer not null,
    drop_weight numeric not null,
    is_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint sea_critters_id_slug_style
        check (id ~ '^[a-z0-9_]+$'),
    constraint sea_critters_display_name_unique
        unique (display_name),
    constraint sea_critters_rarity_valid
        check (rarity in ('common', 'rare', 'ultra_rare')),
    constraint sea_critters_sell_value_positive
        check (sell_value > 0),
    constraint sea_critters_sort_order_unique
        unique (sort_order),
    constraint sea_critters_drop_weight_nonnegative
        check (drop_weight >= 0)
);

create trigger set_public_sea_critters_updated_at
before update on public.sea_critters
for each row
execute function public.set_updated_at();

create index sea_critters_enabled_sort_order_idx
on public.sea_critters (sort_order)
where is_enabled;

create index sea_critters_enabled_rarity_sort_order_idx
on public.sea_critters (rarity, sort_order)
where is_enabled;

alter table public.sea_critters enable row level security;

drop policy if exists "Authenticated users can read enabled sea critters" on public.sea_critters;
create policy "Authenticated users can read enabled sea critters"
on public.sea_critters
for select
to authenticated
using (is_enabled);

revoke all on public.sea_critters from public, anon, authenticated;
grant select on public.sea_critters to authenticated;
