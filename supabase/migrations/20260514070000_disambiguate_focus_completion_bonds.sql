drop function if exists public.award_completed_focus_session_bonds(uuid, timestamptz);

create function public.award_completed_focus_session_bonds(
    target_session_id uuid,
    p_completed_at timestamptz
)
returns void
security definer
set search_path = public
language plpgsql
as $$
declare
    award_record record;
    user_one_village_id uuid;
    user_two_village_id uuid;
begin
    for award_record in
        insert into public.session_bond_awards (
            session_id,
            user_one_id,
            user_two_id,
            awarded_at
        )
        select
            target_session_id,
            least(first_member.user_id, second_member.user_id),
            greatest(first_member.user_id, second_member.user_id),
            p_completed_at
        from public.session_members as first_member
        join public.session_members as second_member
            on second_member.session_id = first_member.session_id
            and second_member.user_id > first_member.user_id
        where first_member.session_id = target_session_id
            and first_member.committed_at is not null
            and second_member.committed_at is not null
        on conflict do nothing
        returning user_one_id, user_two_id
    loop
        insert into public.villager_bonds (
            user_one_id,
            user_two_id,
            completed_pair_sessions,
            first_completed_at,
            last_completed_at
        )
        values (award_record.user_one_id, award_record.user_two_id, 1, p_completed_at, p_completed_at)
        on conflict (user_one_id, user_two_id) do update
        set completed_pair_sessions = public.villager_bonds.completed_pair_sessions + 1,
            first_completed_at = least(public.villager_bonds.first_completed_at, excluded.first_completed_at),
            last_completed_at = greatest(public.villager_bonds.last_completed_at, excluded.last_completed_at);

        select id
        into user_one_village_id
        from public.villages
        where owner_id = award_record.user_one_id;

        if user_one_village_id is null then
            insert into public.villages (owner_id)
            values (award_record.user_one_id)
            on conflict (owner_id) do update
            set owner_id = excluded.owner_id
            returning id into user_one_village_id;
        end if;

        insert into public.village_residents (
            village_id,
            resident_user_id,
            first_completed_session_id,
            unlocked_at
        )
        values (user_one_village_id, award_record.user_two_id, target_session_id, p_completed_at)
        on conflict (village_id, resident_user_id) do nothing;

        select id
        into user_two_village_id
        from public.villages
        where owner_id = award_record.user_two_id;

        if user_two_village_id is null then
            insert into public.villages (owner_id)
            values (award_record.user_two_id)
            on conflict (owner_id) do update
            set owner_id = excluded.owner_id
            returning id into user_two_village_id;
        end if;

        insert into public.village_residents (
            village_id,
            resident_user_id,
            first_completed_session_id,
            unlocked_at
        )
        values (user_two_village_id, award_record.user_one_id, target_session_id, p_completed_at)
        on conflict (village_id, resident_user_id) do nothing;
    end loop;
end;
$$;

revoke all on function public.award_completed_focus_session_bonds(uuid, timestamptz) from public, anon, authenticated;
