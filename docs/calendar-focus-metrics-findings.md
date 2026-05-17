# Calendar Focus Metrics Findings

Read-only discovery for adding a third `Focus` button to the daily calendar overlay hero card.

## Requested Behavior

Add a `Focus` mode beside the existing calendar hero modes. When selected, the hero card should show a daily focus metrics snapshot:

- Total minutes focused
- Solo focus sessions
- Group focus sessions
- Total focus sessions
- Sessions interrupted

This should be available to both free and Plus users, with the existing free-user restriction still applying: free users can only view the current day.

Product semantics confirmed:

- `Total minutes focused` means actual elapsed focused time.
- If a user starts a 30 minute session and interrupts at 25 minutes, total focused time should count 25 minutes.
- `Sessions interrupted` means sessions the current user interrupted, not sessions interrupted by another group member.
- `Group focus sessions` means started group sessions the user was part of.

## Current UI Infrastructure

The calendar overlay already has the right shape for this feature:

- `DailySnapshotHeroMode` currently has two cases: `.fish` and `.bonds`.
- `heroModePills` renders one pill per `DailySnapshotHeroMode.allCases`.
- `DailySnapshotCalendarHero` switches hero content based on the selected mode.
- Free vs Plus day access is already handled through `PicoPlusCapabilities.canAccessDailySnapshot(isPastDay:)`.

Likely UI changes:

- Add `.focus` to `DailySnapshotHeroMode`.
- Add a `Focus` label and icon.
- Add a `DailySnapshotFocusHeroContent` view.
- Extend the hero switch to render focus metrics for `.focus`.

No new entitlement model appears necessary for the UI. The existing calendar detail lock can continue to control past-day access for free users.

## Current Data Infrastructure

`DailySnapshotService` currently fetches:

- `DailyVillageSnapshot`
- `DailySnapshotFocusActivity`

`DailyVillageSnapshot` already includes:

- `focusSessionIDs`
- `totalFocusSeconds`
- fish data
- bond/visitor data

This is enough for the current fish and bond hero modes, but not enough for the requested focus metrics.

The current `fetch_daily_village_snapshot` RPC returns daily snapshot rows and derives `total_focus_seconds` by summing `focus_sessions.duration_seconds` for session IDs stored in `daily_village_snapshots.focus_session_ids`.

That has two important limitations:

- It counts planned duration, not actual elapsed focused time.
- It only covers sessions captured in `daily_village_snapshots`, which are currently written from completed-session reward flow.

Interrupted sessions are handled by `interrupt_focus_session`, which marks:

- `focus_sessions.status = 'failed'`
- `focus_sessions.ended_at`
- `focus_sessions.failed_by_user_id`
- `session_members.failed_at`
- `session_members.failure_reason`

But interrupted sessions do not currently create/update `daily_village_snapshots`.

## Main Gap

The requested metrics should not be derived solely from `daily_village_snapshots.focus_session_ids`.

They need to be aggregated from `focus_sessions` joined to `session_members`, filtered to the current authenticated user and to sessions that actually started.

This is especially important for:

- interrupted-only days
- actual elapsed minutes
- user-specific interruption counts
- solo vs group session counts

## Recommended Backend Shape

Add a Supabase migration that either:

- extends `fetch_daily_village_snapshot` with focus metric fields, or
- adds a dedicated `fetch_daily_focus_metrics(requested_snapshot_day date)` RPC.

Extending `fetch_daily_village_snapshot` is probably simplest for the existing hero card because the calendar already fetches one daily detail payload.

Recommended returned fields:

- `total_focused_seconds integer`
- `solo_focus_sessions integer`
- `group_focus_sessions integer`
- `total_focus_sessions integer`
- `sessions_interrupted integer`

Recommended aggregation basis:

- Join `public.session_members` to `public.focus_sessions`.
- Filter `session_members.user_id = auth.uid()`.
- Require `session_members.committed_at is not null`.
- Require `focus_sessions.started_at is not null`.
- Include finished sessions with `focus_sessions.ended_at is not null`.
- Bucket by the user's private profile timezone, matching existing daily snapshot behavior.
- Use `focus_sessions.ended_at` for the daily bucket, which aligns with the current completion-day snapshot/reward behavior.

Recommended elapsed seconds expression:

- Use `extract(epoch from (focus_sessions.ended_at - focus_sessions.started_at))`.
- Clamp below at `0`.
- Clamp above at `focus_sessions.duration_seconds`.
- Sum the clamped result.

Recommended counts:

- `solo_focus_sessions`: count started committed sessions where `focus_sessions.mode = 'solo'`.
- `group_focus_sessions`: count started committed sessions where `focus_sessions.mode = 'multiplayer'`.
- `total_focus_sessions`: count started committed sessions.
- `sessions_interrupted`: count sessions where the current user's membership shows an own interruption, e.g. `session_members.failed_at is not null` and `session_members.failure_reason in ('interrupted', 'left_multiplayer')`.

Do not count `group_failed` as an interruption by this user.

## Recommended Frontend Shape

Extend the Swift model:

- Add a `DailyFocusMetrics` value type.
- Add it to `DailyVillageSnapshot`, or decode flat fields directly on the snapshot.
- Default all fields to zero when absent, so empty/no-data days render cleanly.

Extend decoding in `DailySnapshotService`:

- Decode the new RPC fields.
- Map `total_focused_seconds` to minutes in the UI with integer minute formatting.

Extend `ContentView.swift` calendar UI:

- Add `case focus` to `DailySnapshotHeroMode`.
- Add label `Focus`.
- Add a suitable icon. If no local asset fits, use an existing app icon asset or a restrained SF Symbol fallback.
- Add `DailySnapshotFocusHeroContent(snapshot:)`.
- Render five metrics in a compact, scan-friendly layout inside the existing hero card height.

## Risks And Decisions

The main product decision is day bucketing. Recommendation: count sessions on the user's local day of `focus_sessions.ended_at`, because existing snapshots are created on completion day in the user's timezone.

If a future requirement needs sessions split across midnight, that is a larger analytics change. The current feature can stay consistent with the existing daily snapshot model by assigning each finished session to its end day.

Backend enforcement for the free current-day restriction should be considered separately. The current client already gates past-day detail for free users, but the existing daily snapshot RPCs do not appear to enforce history access server-side.
