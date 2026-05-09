update public.store_items
set berry_price = case id
    when 'hat:1' then 15
    when 'hat:2' then 150
    when 'hat:3' then 150
    when 'hat:4' then 150
    when 'hat:5' then 1000
    when 'island:sand' then 2000
    else berry_price
end
where id in (
    'hat:1',
    'hat:2',
    'hat:3',
    'hat:4',
    'hat:5',
    'island:sand'
);
