update public.store_items
set berry_price = 1500,
    display_name = 'Shark',
    sort_order = 107
where id = 'hat:5';

update public.store_items
set display_name = case id
        when 'hat:1' then 'Bamboo'
        when 'hat:2' then 'Beanie'
        when 'hat:3' then 'Bow'
        when 'hat:4' then 'Helmet'
        when 'hat:6' then 'Clownfish'
        when 'hat:7' then 'Pufferfish'
        else display_name
    end,
    sort_order = case id
        when 'hat:1' then 101
        when 'hat:2' then 102
        when 'hat:3' then 103
        when 'hat:4' then 104
        when 'hat:7' then 105
        when 'hat:6' then 106
        else sort_order
    end
where id in ('hat:1', 'hat:2', 'hat:3', 'hat:4', 'hat:6', 'hat:7');
