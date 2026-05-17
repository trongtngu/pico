# Calendar Focus Metrics Task

## Source Discovery

- `docs/calendar-focus-metrics-findings.md`
- Before implementing, also read `docs/codex-context.md` per repo instructions.

## Objective

Add a third `Focus` button to the daily calendar overlay hero mode selector. When selected, the hero card should show a snapshot of the user's focus metrics for the selected day:

- Total minutes focused
- Solo focus sessions
- Group focus sessions
- Total focus sessions
- Sessions interrupted

This must work for both free and Plus users. Preserve the existing calendar history rule: free users can only view current-day details; Plus users can view historical day details.

## Product Decisions

- Day bucketing: count a session on the user's local day of `focus_sessions.ended_at`.
- Total focused minutes: use actual elapsed focused time, not planned duration.
- UI rounding: if elapsed time is `25m 40s`, show `26m`. Round up from seconds to whole minutes on the client.
- Empty focus day: show all five metrics with value `0`.
- Group sessions: count started group sessions the user was part of.
- Sessions interrupted: count only sessions the current user interrupted or left during active focus. Do not count sessions where another group member interrupted and this user's membership was marked `group_failed`.
- Backend shape: extend the existing `fetch_daily_village_snapshot` RPC and `DailyVillageSnapshot` model rather than adding a separate focus metrics endpoint.

## Current State

- Calendar overlay UI is in `pico/ContentView.swift`.
- `DailySnapshotHeroMode` currently has `.fish` and `.bonds`.
- `heroModePills` renders all hero modes.
- `DailySnapshotCalendarHero` switches between fish and bond content.
- `DailySnapshotCalendarScreen` loads selected-day detail through `DailySnapshotService.fetchSnapshot`.
- `DailySnapshotService` decodes `DailyVillageSnapshot`, which currently includes `focusSessionIDs`, `totalFocusSeconds`, fish data, and bond visitor data.
- `fetch_daily_village_snapshot` currently derives `total_focus_seconds` from `daily_village_snapshots.focus_session_ids` and `focus_sessions.duration_seconds`.
- `daily_village_snapshots` are currently upserted from completed-session rewards, so interrupted-only days may not have snapshot rows.
- Interrupted sessions are represented in `focus_sessions` and `session_members`, including `focus_sessions.status = 'failed'`, `focus_sessions.ended_at`, `focus_sessions.failed_by_user_id`, `session_members.failed_at`, and `session_members.failure_reason`.

## Work Items

1. Update the Supabase daily snapshot RPC.
   - Add a migration that `create or replace function public.fetch_daily_village_snapshot(requested_snapshot_day date)`.
   - Preserve all existing returned columns used by the app.
   - Add returned integer columns:
     - `total_focused_seconds`
     - `solo_focus_sessions`
     - `group_focus_sessions`
     - `total_focus_sessions`
     - `sessions_interrupted`
   - Aggregate these from `public.session_members` joined to `public.focus_sessions`, not from `daily_village_snapshots.focus_session_ids`.
   - Filter to `session_members.user_id = auth.uid()`.
   - Require `session_members.committed_at is not null`.
   - Require `focus_sessions.started_at is not null`.
   - Require `focus_sessions.ended_at is not null`.
   - Bucket by `(focus_sessions.ended_at at time zone user_timezone)::date = requested_snapshot_day`.
   - Use the same user timezone fallback pattern as `upsert_daily_village_snapshot`: private profile timezone if valid, otherwise `UTC`.

2. Define backend metric semantics.
   - `total_focused_seconds`: sum actual elapsed seconds per session.
   - Compute elapsed seconds from `focus_sessions.ended_at - focus_sessions.started_at`.
   - Clamp elapsed seconds below at `0`.
   - Clamp elapsed seconds above at `focus_sessions.duration_seconds`.
   - `solo_focus_sessions`: count sessions with `focus_sessions.mode = 'solo'`.
   - `group_focus_sessions`: count sessions with `focus_sessions.mode = 'multiplayer'`.
   - `total_focus_sessions`: count all started, committed, finished sessions for the user.
   - `sessions_interrupted`: count only rows where `session_members.failed_at is not null` and `session_members.failure_reason in ('interrupted', 'left_multiplayer')`.
   - Do not count `group_failed` toward `sessions_interrupted`.

3. Preserve existing snapshot behavior.
   - If no `daily_village_snapshots` row exists for an interrupted-only day, the RPC still needs to return a row with focus metrics and empty fish/bond data.
   - For no-data days, return a row or decode path that lets the UI show zero focus metrics. Existing fish/bond empty states should continue to work.
   - Be careful not to break fish and bond hero content that relies on `owner_profile`, `visitors`, `fish_counts`, and `focus_session_ids`.

4. Extend Swift daily snapshot models.
   - Add a `DailyFocusMetrics` value type in `pico/DailySnapshotService.swift`, or equivalent flat fields if that better matches local style.
   - Add metrics to `DailyVillageSnapshot`.
   - Decode the new RPC fields in `DailyVillageSnapshotResponse`.
   - Default all metric fields to zero when absent or null.
   - Consider keeping existing `totalFocusSeconds` as-is for current header behavior unless intentionally replacing it with actual focused seconds.

5. Add the Focus hero mode.
   - Add `case focus` to `DailySnapshotHeroMode`.
   - Add label `Focus`.
   - Add an icon. Prefer an existing app asset if one clearly fits; otherwise use a restrained fallback consistent with the current icon handling.
   - Update `DailySnapshotCalendarHero` to switch on `.focus`.
   - Add `DailySnapshotFocusHeroContent(snapshot:)`.

6. Build the Focus hero content.
   - Show all five metrics, even when values are zero.
   - Round `total_focused_seconds` up to whole minutes for display.
   - Use compact styling that fits within the existing `PicoCalendarStyle.heroContentHeight`.
   - Use existing design tokens, card styling, fonts, and colors.
   - Keep text legible and non-overlapping on compact widths.

7. Keep calendar gating unchanged.
   - Free users should still see the locked hero for past days.
   - Current-day Focus metrics should be visible to free users.
   - Plus users should be able to view historical Focus metrics.
   - Do not add a separate entitlement path unless the existing capability model proves insufficient.

## Suggested SQL Shape

Use this as implementation guidance, not as a required exact query:

```sql
with requester_profile as (
    select case
        when private.user_profiles.user_timezone is not null
             and exists (
                 select 1
                 from pg_timezone_names
                 where name = private.user_profiles.user_timezone
             )
        then private.user_profiles.user_timezone
        else 'UTC'
    end as user_timezone
    from private.user_profiles
    where private.user_profiles.user_id = requester
),
focus_metric_rows as (
    select
        focus_sessions.id,
        focus_sessions.mode,
        greatest(
            0,
            least(
                focus_sessions.duration_seconds,
                extract(epoch from (focus_sessions.ended_at - focus_sessions.started_at))::integer
            )
        ) as elapsed_seconds,
        session_members.failed_at is not null
            and session_members.failure_reason in ('interrupted', 'left_multiplayer') as was_interrupted_by_user
    from public.session_members
    join public.focus_sessions
        on focus_sessions.id = session_members.session_id
    cross join requester_profile
    where session_members.user_id = requester
        and session_members.committed_at is not null
        and focus_sessions.started_at is not null
        and focus_sessions.ended_at is not null
        and (focus_sessions.ended_at at time zone requester_profile.user_timezone)::date = requested_snapshot_day
)
```

## Guardrail Searches

Run these before finishing:

```sh
rg "DailySnapshotHeroMode" pico/ContentView.swift
rg "totalFocusSeconds|totalFocusedSeconds|DailyFocusMetrics" pico/DailySnapshotService.swift pico/ContentView.swift
rg "fetch_daily_village_snapshot" supabase/migrations pico/DailySnapshotService.swift
rg "group_failed|left_multiplayer|interrupted" supabase/migrations pico
```

## Verification

- Build the app.
- Run any relevant Swift tests if available.
- Run Supabase lint if available in the local environment.
- Manually verify calendar overlay behavior:
  - current-day free user can open Focus mode
  - past-day free user still sees the Plus lock
  - Plus user can view historical Focus mode
  - no-session day shows all zero values
  - completed solo session increments solo and total sessions
  - completed group session increments group and total sessions
  - user-interrupted session increments sessions interrupted and contributes actual elapsed minutes
  - group session interrupted by another user does not increment this user's sessions interrupted

## Acceptance Criteria

- The calendar overlay has three hero mode buttons: `Catches`, `Bonds`, and `Focus`.
- Focus mode renders the five requested metrics for the selected day.
- Total minutes focused is based on actual elapsed seconds and rounded up in the UI.
- Metrics include interrupted sessions even when no completed daily village snapshot exists for that day.
- `sessions_interrupted` only counts the current user's own `interrupted` or `left_multiplayer` sessions.
- Existing fish and bond calendar hero behavior continues to work.
- Existing free vs Plus calendar access behavior is preserved.
