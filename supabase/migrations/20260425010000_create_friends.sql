create table public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null,
    recipient_id uuid not null,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint friend_requests_requester_id_fkey
        foreign key (requester_id) references public.user_profiles(user_id) on delete cascade,
    constraint friend_requests_recipient_id_fkey
        foreign key (recipient_id) references public.user_profiles(user_id) on delete cascade,
    constraint friend_requests_different_users
        check (requester_id <> recipient_id),
    constraint friend_requests_status
        check (status in ('pending', 'accepted', 'rejected'))
);

create unique index friend_requests_pending_pair_unique
on public.friend_requests (
    least(requester_id, recipient_id),
    greatest(requester_id, recipient_id)
)
where status = 'pending';

create table public.friendships (
    user_one_id uuid not null,
    user_two_id uuid not null,
    created_at timestamptz not null default now(),
    constraint friendships_pkey primary key (user_one_id, user_two_id),
    constraint friendships_user_one_id_fkey
        foreign key (user_one_id) references public.user_profiles(user_id) on delete cascade,
    constraint friendships_user_two_id_fkey
        foreign key (user_two_id) references public.user_profiles(user_id) on delete cascade,
    constraint friendships_canonical_order
        check (user_one_id < user_two_id)
);

create trigger set_public_friend_requests_updated_at
before update on public.friend_requests
for each row
execute function public.set_updated_at();

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;

create policy "Participants can read friend requests"
on public.friend_requests
for select
to authenticated
using (requester_id = auth.uid() or recipient_id = auth.uid());

create policy "Participants can read friendships"
on public.friendships
for select
to authenticated
using (user_one_id = auth.uid() or user_two_id = auth.uid());

revoke all on public.friend_requests from anon, authenticated;
revoke all on public.friendships from anon, authenticated;

grant select on public.friend_requests to authenticated;
grant select on public.friendships to authenticated;

create or replace function public.send_friend_request(recipient_username text)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    recipient uuid;
    request_id uuid;
    user_one uuid;
    user_two uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to send friend requests.' using errcode = '28000';
    end if;

    select user_id
    into recipient
    from public.user_profiles
    where username = lower(btrim(recipient_username))
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

    select *
    into request_record
    from public.friend_requests
    where id = request_id
        and recipient_id = recipient
        and status = 'pending'
    for update;

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

create or replace function public.reject_friend_request(request_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    recipient uuid := auth.uid();
begin
    if recipient is null then
        raise exception 'You must be signed in to reject friend requests.' using errcode = '28000';
    end if;

    update public.friend_requests
    set status = 'rejected'
    where id = request_id
        and recipient_id = recipient
        and status = 'pending';

    if not found then
        raise exception 'No pending friend request was found.' using errcode = 'P0002';
    end if;

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
    order by friend_requests.created_at desc;
$$;

create or replace function public.list_friends()
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_config jsonb
)
security definer
set search_path = public
language sql
stable
as $$
    select
        user_profiles.user_id,
        user_profiles.username,
        user_profiles.display_name,
        user_profiles.avatar_config
    from public.friendships
    join public.user_profiles
        on user_profiles.user_id = case
            when friendships.user_one_id = auth.uid() then friendships.user_two_id
            else friendships.user_one_id
        end
    where friendships.user_one_id = auth.uid()
        or friendships.user_two_id = auth.uid()
    order by user_profiles.display_name, user_profiles.username;
$$;

revoke all on function public.send_friend_request(text) from public, anon, authenticated;
revoke all on function public.accept_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.reject_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.list_incoming_friend_requests() from public, anon, authenticated;
revoke all on function public.list_friends() from public, anon, authenticated;

grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.reject_friend_request(uuid) to authenticated;
grant execute on function public.list_incoming_friend_requests() to authenticated;
grant execute on function public.list_friends() to authenticated;
