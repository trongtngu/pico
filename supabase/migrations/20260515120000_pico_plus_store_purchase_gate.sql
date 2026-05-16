update public.store_items
set is_paid_only = case when id = 'hat:5' then true else false end
where id in ('island:sand', 'hat:1', 'hat:2', 'hat:3', 'hat:4', 'hat:5');

create or replace function public.purchase_store_item(item_type text, item_key text)
returns table (
    berries bigint,
    completion_streak integer,
    last_completed_on date,
    last_completed_at timestamptz,
    owned_store_item_ids text[]
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    normalized_item_type text := lower(btrim(item_type));
    normalized_item_key text := lower(btrim(item_key));
    selected_item public.store_items%rowtype;
    current_balance public.user_berry_balances%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to buy store items.' using errcode = '28000';
    end if;

    if normalized_item_type is null or normalized_item_type not in ('hat', 'island') then
        raise exception 'Invalid store item type.' using errcode = '22023';
    end if;

    if normalized_item_key is null or normalized_item_key = '' then
        raise exception 'Invalid store item.' using errcode = '22023';
    end if;

    select *
    into selected_item
    from public.store_items
    where store_items.item_type = normalized_item_type
        and store_items.item_key = normalized_item_key
        and store_items.is_enabled
    for update;

    if not found then
        raise exception 'Store item is not available.' using errcode = 'P0002';
    end if;

    if selected_item.is_paid_only and not public.user_has_pico_plus(requester) then
        raise exception 'Pico Plus is required to buy this store item.' using errcode = '42501';
    end if;

    if exists (
        select 1
        from public.user_store_inventory
        where user_store_inventory.user_id = requester
            and user_store_inventory.store_item_id = selected_item.id
    ) then
        raise exception 'You already own that item.' using errcode = '23505';
    end if;

    insert into public.user_berry_balances (user_id)
    values (requester)
    on conflict (user_id) do nothing;

    select *
    into current_balance
    from public.user_berry_balances
    where user_id = requester
    for update;

    if current_balance.berries < selected_item.berry_price then
        raise exception 'Not enough berries.' using errcode = '22003';
    end if;

    update public.user_berry_balances
    set berries = public.user_berry_balances.berries - selected_item.berry_price
    where public.user_berry_balances.user_id = requester
    returning * into current_balance;

    insert into public.user_store_inventory (user_id, store_item_id, acquisition_source)
    values (requester, selected_item.id, 'berries');

    return query
    select
        current_balance.berries,
        current_balance.completion_streak,
        current_balance.last_completed_on,
        current_balance.last_completed_at,
        coalesce(
            array_agg(user_store_inventory.store_item_id order by store_items.item_type, store_items.sort_order)
                filter (where user_store_inventory.store_item_id is not null),
            array[]::text[]
        )
    from (select requester as user_id) as purchase_owner
    left join public.user_store_inventory
        on user_store_inventory.user_id = purchase_owner.user_id
    left join public.store_items
        on store_items.id = user_store_inventory.store_item_id
    group by purchase_owner.user_id;
end;
$$;

revoke all on function public.purchase_store_item(text, text) from public, anon, authenticated;
grant execute on function public.purchase_store_item(text, text) to authenticated;
