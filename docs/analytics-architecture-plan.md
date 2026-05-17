# Analytics Architecture Refactor Plan

## Goal

Replace the current loose analytics layer with a central, typed analytics pipeline.

The new system should make it impossible for feature code to send stray event names,
mistyped parameter keys, or unregistered parameter shapes to Firebase. Adding future
analytics should mean adding a typed event and registering its schema while keeping
the core pipeline unchanged.

Initial product focus: onboarding analytics should map every event to a concrete
dashboard page so we can identify where users drop off.

## Current Problem

The existing analytics implementation is only partially centralized:

- `AnalyticsService.track(...)` is the central sender.
- `AnalyticsEvent` accepts a raw `name` and `[String: Any]` parameters.
- Feature files call analytics directly from views/stores.
- Event definitions are split across extension files.
- There is no central registry that defines which events are valid.
- There is no required/allowed parameter schema per event.
- Firebase receives whatever raw event/parameter shape a call site constructs.

This allows typos, missing dashboard fields, inconsistent event shapes, and accidental
new analytics types to pollute the dataset.

## Target Architecture

### Core Rules

- No raw Firebase event names in feature code.
- No raw analytics parameter strings in feature code.
- No `[String: Any]` outside the Firebase adapter.
- Every event must exist in the analytics catalog before it can be sent.
- Every event must pass required/allowed parameter validation before delivery.
- Common parameters are appended centrally.
- Firebase remains an implementation detail behind the analytics engine.

### Main Types

Create a small typed analytics core:

- `AnalyticsEngine`
- `AnalyticsEvent`
- `AnalyticsEventID`
- `AnalyticsParameterKey`
- `AnalyticsValue`
- `AnalyticsEventDefinition`
- `AnalyticsCatalog`
- `FirebaseAnalyticsEngine`

Example shape:

```swift
protocol AnalyticsEngine {
    func track(_ event: AnalyticsEvent)
}

struct AnalyticsEvent {
    let id: AnalyticsEventID
    let parameters: [AnalyticsParameterKey: AnalyticsValue]
}

enum AnalyticsEventID: String {
    case onboardingStarted = "onboarding_started"
    case onboardingScreenViewed = "onboarding_screen_viewed"
    case onboardingActionTapped = "onboarding_action_tapped"
    case onboardingStepCompleted = "onboarding_step_completed"
    case onboardingExited = "onboarding_exited"
    case onboardingCompleted = "onboarding_completed"
}

enum AnalyticsParameterKey: String {
    case flowName = "flow_name"
    case flowVersion = "flow_version"
    case pageID = "page_id"
    case pageIndex = "page_index"
    case pageCount = "page_count"
    case pageType = "page_type"
    case actionName = "action_name"
    case onboardingVariant = "onboarding_variant"
    case onboardingRunID = "onboarding_run_id"
    case signupMethod = "signup_method"
}

enum AnalyticsValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}
```

### Event Registry

`AnalyticsCatalog` is the source of truth for valid events:

```swift
struct AnalyticsEventDefinition {
    let id: AnalyticsEventID
    let requiredParameters: Set<AnalyticsParameterKey>
    let optionalParameters: Set<AnalyticsParameterKey>
}
```

Before sending, the engine must validate:

- event ID is registered
- required parameters are present
- no unknown parameters are present
- values are Firebase-compatible
- event and parameter names satisfy Firebase limits
- total parameter count stays within Firebase limits after common params are added

### Firebase Adapter

`FirebaseAnalyticsEngine` should be the only place that imports Firebase Analytics
for event delivery.

Responsibilities:

- validate against `AnalyticsCatalog`
- append common params such as `app_version`, `build_number`, and `platform`
- convert typed `AnalyticsValue` to Firebase-compatible `[String: Any]`
- call `Analytics.logEvent(...)`
- handle DEBUG logging and validation warnings

### Central Entry Point

Use one app-level entry point so feature code does not depend on Firebase:

```swift
enum Analytics {
    static let engine: AnalyticsEngine = FirebaseAnalyticsEngine()

    static func track(_ event: AnalyticsEvent) {
        engine.track(event)
    }
}
```

If we later need test injection, we can replace this static entry point with an
environment-injected analytics client. The first refactor should stay small and
aligned with the current app style.

## Onboarding Analytics Layer

Onboarding should use a feature-specific typed helper so views do not hand-assemble
analytics parameters.

Add:

- `OnboardingAnalytics`
- `OnboardingAction`
- `OnboardingPageDefinition`
- `OnboardingFlowContext`

Example call sites:

```swift
onboardingAnalytics.trackStarted()
onboardingAnalytics.trackScreenViewed(step: currentStep)
onboardingAnalytics.trackAction(.next, step: currentStep)
onboardingAnalytics.trackStepCompleted(step: currentStep)
onboardingAnalytics.trackCompleted(method: .email)
```

`OnboardingAnalytics` should always attach the dashboard mapping fields:

- `flow_name`
- `flow_version`
- `page_id`
- `page_index`
- `page_count`
- `page_type`
- `onboarding_variant`
- `onboarding_run_id`

The onboarding view should not send display name text. If needed, send only safe
derived fields such as `has_display_name`.

## Onboarding Dashboard Page Map

Use the ordered onboarding flow as the source of truth:

1. `welcome`
2. `display_name`
3. `rare_fish`
4. `focus_duration`
5. `phone_usage`
6. `focus_intent`
7. `focus_goal`
8. `productivity_experience`
9. `focus_barrier`
10. `why_other_apps_fail`
11. `catch_teaser`
12. `fish_celebration`
13. `reward_celebration`
14. `focus_with_friends`
15. `auth_handoff`

For onboarding-origin email signup, append signup pages to the funnel:

16. `signup_email`
17. `signup_first_name`
18. `signup_username`
19. `signup_password`
20. `account_created`

This allows drop-off reporting by comparing page views, step completions, and next
page views for the same `flow_version` and `page_id`.

## Sequential Implementation Steps

1. Freeze the analytics contract.
   Define and enforce the core rules above before migrating call sites.

2. Create the new typed analytics model.
   Add `AnalyticsEngine`, `AnalyticsEvent`, `AnalyticsEventID`,
   `AnalyticsParameterKey`, `AnalyticsValue`, `AnalyticsEventDefinition`, and
   `AnalyticsCatalog`.

3. Implement the Firebase adapter.
   Add validation, common params, typed value conversion, DEBUG logging, and the
   single Firebase delivery call.

4. Create the central analytics entry point.
   Feature code should call `Analytics.track(...)` or a typed feature helper, not
   Firebase directly.

5. Build the onboarding analytics domain.
   Add typed onboarding helpers, page definitions, flow context, and action enums.

6. Register onboarding events in the catalog.
   Start with `onboarding_started`, `onboarding_screen_viewed`,
   `onboarding_action_tapped`, `onboarding_step_completed`,
   `onboarding_exited`, and `onboarding_completed`.

7. Remove the old analytics model.
   Delete or fully replace the loose `AnalyticsService`, raw `AnalyticsEvent`, and
   feature event extension files as part of the clean cut.

8. Migrate onboarding call sites.
   Replace direct analytics calls in onboarding with typed onboarding analytics
   helper calls.

9. Migrate auth/signup events that are part of onboarding.
   The onboarding funnel continues through auth handoff and email signup. Include
   signup start, signup step views, signup step completions, signup completion, and
   onboarding completion.

10. Migrate remaining existing analytics events.
    Move focus, home, catch reveal, fish sold, Pico Plus paywall, and Pico Plus gate
    events into the new catalog so no old engine references remain.

11. Add guardrail checks.
    Use repository search during review to ensure there are no remaining references
    to the old analytics API or direct Firebase event delivery outside the adapter.

12. Verify.
    Build the app, run relevant tests if available, and manually check DEBUG
    analytics logs through the onboarding flow.

13. Register Firebase custom dimensions.
    Register dashboard fields such as `flow_name`, `flow_version`, `page_id`,
    `page_index`, `page_type`, `action_name`, `onboarding_variant`, and
    `signup_method` in Firebase/GA4.

## Cleanup Checks

After migration, these searches should return no feature call sites:

```sh
rg "AnalyticsService" pico
rg "AnalyticsEvent\\(name:" pico
rg "Analytics\\.logEvent" pico
rg "\\[String: Any\\]" pico/Analytics*.swift
```

`Analytics.logEvent` should only appear in `FirebaseAnalyticsEngine`.

## Notes

Keep the first implementation deliberately small. The important architectural win is
the typed catalog and validation pipeline, not a large abstraction framework.

Feature-specific helpers should be thin wrappers over the central typed event model.
The engine should validate and deliver events; it should not own onboarding or other
feature-specific business logic.
