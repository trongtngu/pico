create or replace function public.complete_focus_session_with_score(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    completed_session jsonb;
    score_payload jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to complete a focus session.' using errcode = '28000';
    end if;

    completed_session := public.complete_focus_session(target_session_id);

    select jsonb_build_object(
        'score', coalesce(user_scores.score, 0)::bigint,
        'current_streak', coalesce(user_scores.current_streak, 0)::integer,
        'last_scored_on', user_scores.last_scored_on,
        'last_scored_at', user_scores.last_scored_at
    )
    into score_payload
    from (select requester as user_id) as score_requester
    left join public.user_scores
        on user_scores.user_id = score_requester.user_id;

    return jsonb_build_object(
        'session', completed_session,
        'score', score_payload
    );
end;
$$;

revoke all on function public.complete_focus_session_with_score(uuid) from public, anon, authenticated;
grant execute on function public.complete_focus_session_with_score(uuid) to authenticated;
