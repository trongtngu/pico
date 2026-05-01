create or replace function public.avatar_hat_berry_cost(hat integer)
returns bigint
language sql
immutable
set search_path = public
as $$
    select case hat
        when 0 then 0
        when 1 then 3
        when 2 then 10
        when 3 then 20
        when 4 then 30
        else null
    end;
$$;

create or replace function public.purchase_avatar_hat(hat integer)
returns table (
    score bigint,
    current_streak integer,
    last_scored_on date,
    last_scored_at timestamptz,
    owned_hats integer[]
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    requested_hat integer := $1;
    hat_cost bigint;
    current_score public.user_scores%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to buy hats.' using errcode = '28000';
    end if;

    hat_cost := public.avatar_hat_berry_cost(requested_hat);

    if hat_cost is null or requested_hat = 0 then
        raise exception 'Invalid avatar hat.' using errcode = '22023';
    end if;

    insert into public.user_scores (user_id)
    values (requester)
    on conflict (user_id) do nothing;

    select *
    into current_score
    from public.user_scores
    where user_id = requester
    for update;

    if exists (
        select 1
        from public.user_hat_inventory
        where
            user_hat_inventory.user_id = requester
            and user_hat_inventory.hat = requested_hat
    ) then
        raise exception 'You already own that hat.' using errcode = '23505';
    end if;

    if current_score.score < hat_cost then
        raise exception 'Not enough berries.' using errcode = '22003';
    end if;

    update public.user_scores
    set score = public.user_scores.score - hat_cost
    where public.user_scores.user_id = requester
    returning *
    into current_score;

    insert into public.user_hat_inventory (user_id, hat)
    values (requester, requested_hat);

    return query
    select
        current_score.score,
        current_score.current_streak,
        current_score.last_scored_on,
        current_score.last_scored_at,
        coalesce(
            array_agg(user_hat_inventory.hat order by user_hat_inventory.hat)
                filter (where user_hat_inventory.hat is not null),
            array[]::integer[]
        )
    from (select requester as user_id) as purchase_owner
    left join public.user_hat_inventory
        on user_hat_inventory.user_id = purchase_owner.user_id
    group by purchase_owner.user_id;
end;
$$;

revoke all on function public.avatar_hat_berry_cost(integer) from public, anon, authenticated;
revoke all on function public.purchase_avatar_hat(integer) from public, anon, authenticated;
grant execute on function public.purchase_avatar_hat(integer) to authenticated;
