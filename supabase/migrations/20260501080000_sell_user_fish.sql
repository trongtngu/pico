create or replace function public.sell_user_fish(catch_ids uuid[])
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    sold_fish_count integer,
    sold_berry_amount bigint,
    sold_bass integer,
    sold_salmon integer,
    sold_tuna integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    sold_time timestamptz := now();
    requested_count integer;
    distinct_requested_count integer;
    locked_count integer;
    already_sold_count integer;
    sold_amount bigint := 0;
    sold_count integer := 0;
    bass_count integer := 0;
    salmon_count integer := 0;
    tuna_count integer := 0;
    updated_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to sell fish.' using errcode = '28000';
    end if;

    requested_count := coalesce(cardinality(catch_ids), 0);
    if requested_count = 0 then
        raise exception 'Choose at least one fish to sell.' using errcode = '22023';
    end if;

    select count(distinct requested_catch_id)
    into distinct_requested_count
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    if distinct_requested_count <> requested_count then
        raise exception 'Fish can only be sold once per request.' using errcode = '22023';
    end if;

    drop table if exists pg_temp.requested_fish_sale_ids;
    drop table if exists pg_temp.locked_fish_sale_rows;

    create temporary table requested_fish_sale_ids (
        id uuid primary key
    ) on commit drop;

    insert into requested_fish_sale_ids (id)
    select requested_catch_id
    from unnest(catch_ids) as requested_catches(requested_catch_id);

    create temporary table locked_fish_sale_rows
    on commit drop
    as
    select user_fish_catches.*
    from public.user_fish_catches
    join requested_fish_sale_ids
        on requested_fish_sale_ids.id = user_fish_catches.id
    where user_fish_catches.user_id = requester
    for update of user_fish_catches;

    select count(*)
    into locked_count
    from locked_fish_sale_rows;

    if locked_count <> requested_count then
        raise exception 'One or more selected fish could not be found.' using errcode = 'P0002';
    end if;

    select count(*)
    into already_sold_count
    from locked_fish_sale_rows
    where sold_at is not null;

    if already_sold_count > 0 then
        raise exception 'One or more selected fish has already been sold.' using errcode = '23514';
    end if;

    with sold_rows as (
        update public.user_fish_catches
        set sold_at = sold_time,
            sold_for_berries = public.user_fish_catches.sell_value
        from requested_fish_sale_ids
        where public.user_fish_catches.id = requested_fish_sale_ids.id
            and public.user_fish_catches.user_id = requester
            and public.user_fish_catches.sold_at is null
        returning public.user_fish_catches.fish_type, public.user_fish_catches.sell_value
    )
    select
        count(*)::integer,
        coalesce(sum(sell_value), 0)::bigint,
        count(*) filter (where fish_type = 'bass')::integer,
        count(*) filter (where fish_type = 'salmon')::integer,
        count(*) filter (where fish_type = 'tuna')::integer
    into sold_count, sold_amount, bass_count, salmon_count, tuna_count
    from sold_rows;

    if sold_count <> requested_count then
        raise exception 'One or more selected fish could not be sold.' using errcode = '40001';
    end if;

    insert into public.user_berry_balances (user_id, berries)
    values (requester, sold_amount)
    on conflict (user_id) do update
    set berries = public.user_berry_balances.berries + excluded.berries
    returning *
    into updated_balance;

    return query
    select
        updated_balance.berries,
        updated_balance.completion_streak,
        updated_balance.last_completed_on,
        updated_balance.last_completed_at,
        sold_count,
        sold_amount,
        bass_count,
        salmon_count,
        tuna_count;
end;
$$;

revoke all on function public.sell_user_fish(uuid[]) from public, anon, authenticated;
grant execute on function public.sell_user_fish(uuid[]) to authenticated;

notify pgrst, 'reload schema';
