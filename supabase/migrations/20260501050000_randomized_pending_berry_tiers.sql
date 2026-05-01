alter table public.pending_berry_rewards
    add column if not exists black_berries integer not null default 0,
    add column if not exists white_berries integer not null default 0,
    add column if not exists red_berries integer not null default 0;

update public.pending_berry_rewards
set black_berries = greatest(berry_amount, 0)::integer,
    white_berries = 0,
    red_berries = 0
where black_berries = 0
    and white_berries = 0
    and red_berries = 0;

alter table public.pending_berry_rewards
    drop constraint if exists pending_berry_rewards_amount_positive,
    drop constraint if exists pending_berry_rewards_tier_counts_valid,
    drop constraint if exists pending_berry_rewards_tier_total_matches;

alter table public.pending_berry_rewards
    add constraint pending_berry_rewards_tier_counts_valid
        check (
            black_berries >= 0
            and white_berries >= 0
            and red_berries >= 0
        ),
    add constraint pending_berry_rewards_tier_total_matches
        check (
            berry_amount = black_berries + (white_berries * 2) + (red_berries * 3)
            and berry_amount >= 3
        );

create or replace function public.random_pending_berry_reward()
returns table (
    black_berries integer,
    white_berries integer,
    red_berries integer,
    berry_amount bigint
)
security definer
set search_path = public
language plpgsql
as $$
declare
    draw_index integer;
    roll double precision;
    black_count integer := 0;
    white_count integer := 0;
    red_count integer := 0;
begin
    -- Three weighted drops: black 80%, white 16%, red 4%.
    for draw_index in 1..3 loop
        roll := random();

        if roll < 0.04 then
            red_count := red_count + 1;
        elsif roll < 0.20 then
            white_count := white_count + 1;
        else
            black_count := black_count + 1;
        end if;
    end loop;

    return query
    select
        black_count,
        white_count,
        red_count,
        (black_count + (white_count * 2) + (red_count * 3))::bigint;
end;
$$;

create or replace function public.create_pending_berry_reward(
    completing_user_id uuid,
    target_session_id uuid
)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
    reward record;
begin
    select *
    into reward
    from public.random_pending_berry_reward();

    insert into public.pending_berry_rewards (
        user_id,
        session_id,
        berry_amount,
        black_berries,
        white_berries,
        red_berries
    )
    values (
        completing_user_id,
        target_session_id,
        reward.berry_amount,
        reward.black_berries,
        reward.white_berries,
        reward.red_berries
    )
    on conflict (user_id, session_id) do nothing;
end;
$$;

drop function if exists public.collect_pending_berry_rewards();

create or replace function public.collect_pending_berry_rewards()
returns table (
    score bigint,
    current_streak integer,
    last_scored_on date,
    last_scored_at timestamptz,
    collected_berry_amount bigint,
    collected_reward_count integer,
    collected_black_berries integer,
    collected_white_berries integer,
    collected_red_berries integer
)
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    collected_amount bigint := 0;
    reward_count integer := 0;
    black_count integer := 0;
    white_count integer := 0;
    red_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to collect berries.' using errcode = '28000';
    end if;

    with collected_rewards as (
        update public.pending_berry_rewards
        set collected_at = now()
        where user_id = requester
            and collected_at is null
        returning berry_amount, black_berries, white_berries, red_berries
    )
    select
        coalesce(sum(berry_amount), 0)::bigint,
        count(*)::integer,
        coalesce(sum(black_berries), 0)::integer,
        coalesce(sum(white_berries), 0)::integer,
        coalesce(sum(red_berries), 0)::integer
    into collected_amount, reward_count, black_count, white_count, red_count
    from collected_rewards;

    insert into public.user_scores (user_id, score)
    values (requester, collected_amount)
    on conflict (user_id) do update
    set score = public.user_scores.score + excluded.score;

    return query
    select
        coalesce(user_scores.score, 0)::bigint,
        coalesce(user_scores.current_streak, 0)::integer,
        user_scores.last_scored_on,
        user_scores.last_scored_at,
        collected_amount,
        reward_count,
        black_count,
        white_count,
        red_count
    from (select requester as user_id) as score_requester
    left join public.user_scores
        on user_scores.user_id = score_requester.user_id;
end;
$$;

revoke all on function public.random_pending_berry_reward() from public, anon, authenticated;
revoke all on function public.create_pending_berry_reward(uuid, uuid) from public, anon, authenticated;
revoke all on function public.collect_pending_berry_rewards() from public, anon, authenticated;

grant execute on function public.collect_pending_berry_rewards() to authenticated;

notify pgrst, 'reload schema';
