# Analytics Refactor Task

## Source Plan

- `docs/analytics-architecture-plan.md`

## Objective

Replace the current raw analytics layer with a typed, catalog-backed analytics
pipeline. Feature code should not send raw Firebase event names, raw parameter
keys, or arbitrary `[String: Any]` payloads.

Initial product goal: onboarding and onboarding-origin signup analytics should
map every event to a dashboard page so drop-off can be measured by flow version,
page ID, and run ID.

## Current State

- `pico/AnalyticsService.swift` imports Firebase Analytics and sends events.
- `pico/AnalyticsEvent.swift` accepts raw event names and `[String: Any]`.
- Event factories are split across `AnalyticsEvents+Onboarding.swift`,
  `AnalyticsEvents+Focus.swift`, and `AnalyticsEvents+PicoPlus.swift`.
- Feature call sites invoke `AnalyticsService.track(...)` directly from views
  and stores.

## Work Items

1. Define the typed analytics contract.
   - Add `AnalyticsEngine`, `AnalyticsEvent`, `AnalyticsEventID`,
     `AnalyticsParameterKey`, `AnalyticsValue`, `AnalyticsEventDefinition`,
     and `AnalyticsCatalog`.
   - Ensure event names and parameter keys are represented by typed enums.
   - Keep `[String: Any]` out of feature code.

2. Implement the Firebase adapter.
   - Add `FirebaseAnalyticsEngine`.
   - Validate events against `AnalyticsCatalog`.
   - Append common params centrally: `app_version`, `build_number`, `platform`.
   - Convert `AnalyticsValue` to Firebase-compatible values.
   - Keep `Analytics.logEvent(...)` isolated to this adapter.

3. Add the central entry point.
   - Add `Analytics.track(_:)`.
   - Preserve user ID and user property support if still needed by the app.

4. Build the onboarding analytics helper layer.
   - Add `OnboardingAnalytics`.
   - Add typed `OnboardingAction`, `OnboardingPageDefinition`, and
     `OnboardingFlowContext`.
   - Always attach dashboard mapping fields:
     `flow_name`, `flow_version`, `page_id`, `page_index`, `page_count`,
     `page_type`, `onboarding_variant`, and `onboarding_run_id`.
   - Do not send display-name text. Use safe derived fields only if needed.

5. Register onboarding events.
   - `onboarding_started`
   - `onboarding_screen_viewed`
   - `onboarding_action_tapped`
   - `onboarding_step_completed`
   - `onboarding_exited`
   - `onboarding_completed`

6. Map onboarding pages.
   - Use `OnboardingStep.ordered` as the source of truth.
   - Preserve page IDs:
     `welcome`, `display_name`, `rare_fish`, `focus_duration`, `phone_usage`,
     `focus_intent`, `focus_goal`, `productivity_experience`,
     `focus_barrier`, `why_other_apps_fail`, `catch_teaser`,
     `fish_celebration`, `reward_celebration`, `focus_with_friends`,
     `auth_handoff`.

7. Extend the onboarding funnel through email signup.
   - Map signup pages:
     `signup_email`, `signup_first_name`, `signup_username`,
     `signup_password`, `account_created`.
   - Track signup start, signup page views, signup step completions, signup
     completion, and onboarding completion for onboarding-origin signup.
   - Treat `account_created` as a synthetic completion page unless the UI gains
     a real account-created screen.

8. Migrate remaining existing analytics events.
   - Focus/home events.
   - Catch reveal and fish sold events.
   - Pico Plus entitlement, paywall, and gate events.

9. Remove the old loose analytics API.
   - Delete or fully replace `AnalyticsService`.
   - Delete raw `AnalyticsEvent(name:)` construction.
   - Remove old event extension files once their events are migrated.

## Guardrail Searches

These should return no feature call sites before the task is considered done:

```sh
rg "AnalyticsService" pico
rg "AnalyticsEvent\\(name:" pico
rg "Analytics\\.logEvent" pico
rg "\\[String: Any\\]" pico/Analytics*.swift
```

`Analytics.logEvent` should only appear in `FirebaseAnalyticsEngine`.

## Verification

- Build the app.
- Run relevant tests if available.
- Manually exercise onboarding in DEBUG and inspect analytics logs for:
  - registered event IDs only
  - required dashboard fields present
  - stable `onboarding_run_id` across one funnel run
  - correct page order and page IDs
  - no display-name, email, username, or password values in analytics payloads

## External Follow-Up

Register Firebase/GA4 custom dimensions for dashboard fields:

- `flow_name`
- `flow_version`
- `page_id`
- `page_index`
- `page_type`
- `action_name`
- `onboarding_variant`
- `signup_method`
