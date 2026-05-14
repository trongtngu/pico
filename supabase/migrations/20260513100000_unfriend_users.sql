create or replace function public.unfriend_user(friend_user_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    user_one uuid;
    user_two uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to unfriend users.' using errcode = '28000';
    end if;

    if friend_user_id is null then
        raise exception 'Choose a friend to unfriend.' using errcode = '22023';
    end if;

    if requester = friend_user_id then
        raise exception 'You cannot unfriend yourself.' using errcode = '22023';
    end if;

    user_one := least(requester, friend_user_id);
    user_two := greatest(requester, friend_user_id);

    delete from public.friendships
    where user_one_id = user_one
        and user_two_id = user_two;

    if not found then
        raise exception 'You are not friends with that user.' using errcode = 'P0002';
    end if;

    delete from public.villager_bonds
    where user_one_id = user_one
        and user_two_id = user_two;

    delete from public.village_residents
    using public.villages
    where village_residents.village_id = villages.id
        and (
            (
                villages.owner_id = requester
                and village_residents.resident_user_id = friend_user_id
            )
            or (
                villages.owner_id = friend_user_id
                and village_residents.resident_user_id = requester
            )
        );

    return jsonb_build_object('id', friend_user_id);
end;
$$;

revoke all on function public.unfriend_user(uuid) from public, anon, authenticated;
grant execute on function public.unfriend_user(uuid) to authenticated;
