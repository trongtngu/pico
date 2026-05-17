alter table public.user_profiles
add column if not exists profile_completed_at timestamptz;

update public.user_profiles
set profile_completed_at = coalesce(profile_completed_at, updated_at, created_at, now())
where profile_completed_at is null
    and username !~ '^pico_[0-9a-f]{19}$';

create or replace function public.set_user_profile_completion()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.username ~ '^[a-z0-9_]{3,24}$'
        and new.username !~ '^pico_[0-9a-f]{19}$'
        and new.display_name = btrim(new.display_name)
        and char_length(new.display_name) between 1 and 40
    then
        new.profile_completed_at := coalesce(
            new.profile_completed_at,
            case when tg_op = 'UPDATE' then old.profile_completed_at end,
            now()
        );
    else
        new.profile_completed_at := null;
    end if;

    return new;
end;
$$;

drop trigger if exists set_public_user_profile_completion on public.user_profiles;

create trigger set_public_user_profile_completion
before insert or update of username, display_name, avatar_config, profile_completed_at on public.user_profiles
for each row execute function public.set_user_profile_completion();

drop policy if exists "Authenticated users can read public profiles" on public.user_profiles;

create policy "Authenticated users can read completed public profiles"
on public.user_profiles
for select
to authenticated
using (
    user_id = auth.uid()
        or profile_completed_at is not null
);

create or replace function public.send_friend_request(recipient_username text)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    requester_completed_at timestamptz;
    recipient uuid;
    request_id uuid;
    user_one uuid;
    user_two uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to send friend requests.' using errcode = '28000';
    end if;

    select profile_completed_at
    into requester_completed_at
    from public.user_profiles
    where user_id = requester
    limit 1;

    if requester_completed_at is null then
        raise exception 'Finish your profile before sending friend requests.' using errcode = '22023';
    end if;

    select user_id
    into recipient
    from public.user_profiles
    where username = lower(btrim(recipient_username))
        and profile_completed_at is not null
    limit 1;

    if recipient is null then
        raise exception 'No user found for that username.' using errcode = 'P0002';
    end if;

    if requester = recipient then
        raise exception 'You cannot add yourself as a friend.' using errcode = '22023';
    end if;

    user_one := least(requester, recipient);
    user_two := greatest(requester, recipient);

    if exists (
        select 1
        from public.friendships
        where user_one_id = user_one
            and user_two_id = user_two
    ) then
        raise exception 'You are already friends.' using errcode = '23505';
    end if;

    if exists (
        select 1
        from public.friend_requests
        where status = 'pending'
            and least(requester_id, recipient_id) = user_one
            and greatest(requester_id, recipient_id) = user_two
    ) then
        raise exception 'A friend request is already pending.' using errcode = '23505';
    end if;

    insert into public.friend_requests (requester_id, recipient_id)
    values (requester, recipient)
    returning id into request_id;

    return jsonb_build_object('id', request_id);
end;
$$;

create or replace function public.accept_friend_request(request_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    recipient uuid := auth.uid();
    request_record public.friend_requests%rowtype;
    user_one uuid;
    user_two uuid;
begin
    if recipient is null then
        raise exception 'You must be signed in to accept friend requests.' using errcode = '28000';
    end if;

    select friend_requests.*
    into request_record
    from public.friend_requests
    join public.user_profiles as requester_profiles
        on requester_profiles.user_id = friend_requests.requester_id
    join public.user_profiles as recipient_profiles
        on recipient_profiles.user_id = friend_requests.recipient_id
    where friend_requests.id = request_id
        and friend_requests.recipient_id = recipient
        and friend_requests.status = 'pending'
        and requester_profiles.profile_completed_at is not null
        and recipient_profiles.profile_completed_at is not null
    for update of friend_requests;

    if not found then
        raise exception 'No pending friend request was found.' using errcode = 'P0002';
    end if;

    update public.friend_requests
    set status = 'accepted'
    where id = request_id;

    user_one := least(request_record.requester_id, request_record.recipient_id);
    user_two := greatest(request_record.requester_id, request_record.recipient_id);

    insert into public.friendships (user_one_id, user_two_id)
    values (user_one, user_two)
    on conflict do nothing;

    return jsonb_build_object('id', request_id);
end;
$$;

create or replace function public.list_incoming_friend_requests()
returns table (
    id uuid,
    requester_id uuid,
    username text,
    display_name text,
    avatar_config jsonb,
    created_at timestamptz
)
security definer
set search_path = public
language sql
stable
as $$
    select
        friend_requests.id,
        user_profiles.user_id as requester_id,
        user_profiles.username,
        user_profiles.display_name,
        user_profiles.avatar_config,
        friend_requests.created_at
    from public.friend_requests
    join public.user_profiles
        on user_profiles.user_id = friend_requests.requester_id
    where friend_requests.recipient_id = auth.uid()
        and friend_requests.status = 'pending'
        and user_profiles.profile_completed_at is not null
    order by friend_requests.created_at desc;
$$;

create or replace function public.is_username_available(target_username text)
returns boolean
language sql
security definer
set search_path = ''
as $$
    select lower(btrim(target_username)) ~ '^[a-z0-9_]{3,24}$'
        and lower(btrim(target_username)) !~ '^pico_[0-9a-f]{19}$'
        and not exists (
            select 1
            from public.user_profiles
            where user_profiles.username = lower(btrim(target_username))
            limit 1
        );
$$;

revoke all on function public.set_user_profile_completion() from public, anon, authenticated;
revoke all on function public.send_friend_request(text) from public, anon, authenticated;
revoke all on function public.accept_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.list_incoming_friend_requests() from public, anon, authenticated;
revoke all on function public.is_username_available(text) from public, anon, authenticated;

grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.list_incoming_friend_requests() to authenticated;
grant execute on function public.is_username_available(text) to anon, authenticated;
