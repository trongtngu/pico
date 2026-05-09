insert into public.store_items (
    id,
    item_type,
    item_key,
    display_name,
    berry_price,
    is_enabled,
    is_limited,
    is_paid_only,
    sort_order,
    metadata
)
values (
    'hat:5',
    'hat',
    '5',
    'Shark Hat',
    1000,
    true,
    false,
    false,
    105,
    '{"hat": 5}'::jsonb
)
on conflict (id) do update
set item_type = excluded.item_type,
    item_key = excluded.item_key,
    display_name = excluded.display_name,
    berry_price = excluded.berry_price,
    is_enabled = excluded.is_enabled,
    is_limited = excluded.is_limited,
    is_paid_only = excluded.is_paid_only,
    sort_order = excluded.sort_order,
    metadata = excluded.metadata;
