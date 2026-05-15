# Pico Plus Subscription Gating Discovery

This discovery is based on `docs/codex-context.md` plus targeted inspection of the current Swift and Supabase code. It is intentionally read-only analysis; no Pico Plus implementation is included here.

## 1. Where Subscription/Paywall Logic Should Live

- Add a small app-wide subscription layer owned near the signed-in composition root in `pico/ContentView.swift`. `AppShellView` already owns shared stores and injects them through the environment, so a future `PicoPlusStore` or `SubscriptionStore` should probably be created there beside `FriendStore`, `FocusStore`, `VillageStore`, `BerryStore`, `FishStore`, and `IslandStore`.
- Keep entitlement state out of individual views where possible. Views such as `HomePage`, `StartFocusSheet`, `StorePage`, `ProfilePage`, and `DailySnapshotCalendarScreen` should consume simple capabilities like `canCreateLargeGroups`, `canUsePlusCosmetics`, `berryMultiplier`, and `historyWindowDays`.
- Put paywall presentation behind a reusable gate object/helper, not inline in each feature. A good shape would be:
  - `pico/PicoPlusStore.swift` for `@Published` entitlement/capability state and refresh.
  - `pico/PicoPlusService.swift` for Superwall/subscription SDK calls and optional backend entitlement fetch.
  - `pico/PicoPlusEntitlements.swift` for local capability constants/free limits.
- Server-authoritative checks are needed for anything that changes data or rewards. Client gates can improve UX, but Supabase RPCs should enforce group-size limits, paid-only item grants, and berry/fish reward multipliers.
- SuperwallKit is already linked but unused: package reference/product in `pico.xcodeproj/project.pbxproj`, and resolved `superwall-ios` version `4.15.1` in `pico.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## 2. Existing Onboarding/Paywall Files

- `pico/AuthViews.swift` owns signed-out routing. `AuthGateView` switches between auth/onboarding and `AppShellView`; `AuthRootView` routes `.entry`, `.onboarding`, `.login`, `.signupOptions`, and `.signup`.
- `pico/OnboardingViews.swift` owns `OnboardingSequenceView`, onboarding state, analytics tracking, and the ordered onboarding steps. Existing steps include `rareFish`, `rewardCelebration`, `focusWithFriends`, and `authHandoff`, but there is no current subscription/paywall step.
- `pico.xcodeproj/project.pbxproj` links `SuperwallKit`, but there are no `import SuperwallKit`, `Superwall`, `paywall`, `subscription`, or `entitlement` usages in app source.
- `pico/ContentView.swift` is the current post-login feature shell and likely the first place a post-onboarding or feature-triggered paywall would be presented.

## 3. Existing User/Account/Session Models That May Need Subscription State

- `pico/AuthService.swift`
  - `AuthSession` has access token, refresh token, `AuthUser`, and expiry only.
  - `AuthUser` has `id` and `email` only.
  - `UserProfile` has `userID`, `username`, `displayName`, and `avatarConfig` only.
  - `fetchProfile` reads `user_profiles?select=user_id,username,display_name,avatar_config`.
- `pico/AuthSessionStore.swift`
  - Owns `session`, `profile`, `ownedStoreItemIDs`, `ownedHats`, and `ownedIslandIDs`.
  - Validates owned hats before saving profile changes.
  - Loads profile and store inventory together, which makes it a natural consumer of subscription-derived cosmetic grants if those grants are reflected as inventory.
- `pico/FocusService.swift`
  - `FocusSession`, `FocusSessionMember`, `FocusSessionDetail`, and `FocusSessionInvite` have no subscription fields.
  - `FocusService.inviteMembers` sends only `targetSessionId` and `inviteeIds`; there is no plan/member limit model in the client payload.
- `pico/BerryService.swift`
  - `UserBerryBalance` has berries and streak state only.
  - `StoreItem` already has `isPaidOnly`, which is not an entitlement but is the closest existing paid-cosmetic flag.
- `pico/DailySnapshotService.swift`
  - `DailyVillageSnapshot` and `DailySnapshotFocusActivity` have no entitlement context; history availability is currently determined entirely by requested date/range and server response.
- `supabase/migrations/20260513090000_init_clean_schema.sql`
  - `public.user_profiles` and `private.user_profiles` have no subscription columns.
  - `public.user_berry_balances` has balance/streak only.
  - `public.focus_sessions` and `public.session_members` have no plan or max-member fields.
  - `public.store_items.is_paid_only` exists, and `purchase_store_item` rejects those items for berry purchase.

## 4. Screens That Need Gating

### Larger Group Sessions

- Main UI path: `pico/ContentView.swift`
  - `HomePage` opens `StartFocusSheet`.
  - `FocusModePickerSheetContent` exposes "With friends".
  - `MultiplayerInviteFriendsSheetContent` selects any number of available friends and calls `focusStore.inviteFriends`.
  - `MultiplayerLobbySheetContent` lets the host invite more and start once at least one non-host joined member exists.
- Store/service path:
  - `pico/FocusStore.swift` creates lobbies and invites friends.
  - `pico/FocusService.swift` calls `create_focus_session`, `invite_focus_session_members`, and `start_focus_session`.
  - `supabase/migrations/20260513090000_init_clean_schema.sql` function `invite_focus_session_members` currently loops all invitee IDs and has no group-size limit.
- Suggested gate: allow free users to create/join small multiplayer sessions, then require Pico Plus for group size above the agreed free cap. Enforce in both `MultiplayerInviteFriendsSheetContent` selection/UI and `invite_focus_session_members`.

### Plus Cosmetics

- Store/catalog path:
  - `pico/BerryService.swift` models `StoreItem.isPaidOnly`.
  - `pico/ContentView.swift` store rows and preview overlays show paid-only items as `"Paid"` and prevent berry purchase.
  - `supabase/migrations/20260513090000_init_clean_schema.sql` has `store_items.is_paid_only`, and `purchase_store_item` rejects paid-only items with `"This store item cannot be bought with berries."`
- Profile/avatar path:
  - `pico/AvatarCatalog.swift` defines `AvatarHat`.
  - `pico/AuthSessionStore.swift` derives `ownedHats` from store inventory.
  - `pico/ContentView.swift` `ProfilePage` and `ProfileAvatarOutfitCard` display locked hats and block saving unowned hats.
- Suggested gate: decide whether Plus cosmetics are direct entitlements, inventory grants with `acquisition_source = 'subscription'`, or paid-only store catalog items unlocked by active Plus. Inventory grants fit the existing ownership checks best.

### Friend Scarves/Cosmetics

- `pico/AvatarCatalog.swift` defines `AvatarScarf` from bond level 2 through 5.
- `pico/VillageStore.swift` maps a friend user ID to `AvatarScarf(bondLevel:)`.
- Friend scarves render in several places:
  - `pico/VillageViews.swift` for village/focus island participants.
  - `pico/ContentView.swift` `FocusMemberStatusRow`.
  - `pico/FriendViews.swift` `FriendProfilePage`.
- Supabase source:
  - `list_village_residents` returns `bond_level`.
  - `upsert_daily_village_snapshot` captures visitor `bond_level`.
- Suggested gate: if "friend scarves/cosmetics" means paid visual treatment, do not overload bond-level scarves without a product decision. Add an explicit cosmetic entitlement/selection model, or treat extra scarf styles as Plus-only inventory while preserving bond-level progression.

### Faster Berry Gain

- Current direct berries are mainly from selling fish, not from completing focus directly:
  - `record_user_completion_streak` updates streak data but inserts `berries = 0`.
  - `create_focus_session_fish_catches` creates more fish for longer sessions.
  - `sell_user_fish` adds the sold fish sell value into `user_berry_balances`.
- Client refresh points:
  - `pico/ContentView.swift` reloads berry balance after focus completion flows and store/fish selling.
  - `pico/BerryStore.swift` owns displayed balance.
- Suggested gate: implement the multiplier server-side where value is minted, likely in `create_focus_session_fish_catches`, `random_fish_catches_with_rarity_bonus`, and/or `sell_user_fish`. If the promise is "faster berry gain", document whether it means more fish, higher fish sell values, bonus berries on completion, or a sale multiplier.

### Extended Calendar/History

- UI path:
  - `pico/ContentView.swift` `HomeTopBarCalendarStats` opens the calendar.
  - `DailySnapshotCalendarScreen` lets users navigate to any previous month; only future days are disabled.
- Service/RPC path:
  - `pico/DailySnapshotService.swift` calls `fetch_daily_village_snapshot` for selected days and `list_daily_focus_activity` for month ranges.
  - `list_daily_focus_activity` only caps the request span to 63 days; it does not restrict how far back the user can go.
  - `fetch_daily_village_snapshot` has no age/window restriction.
- Suggested gate: add a free history window in both UI navigation/day selection and Supabase RPCs. For example, free users can view the recent N days/months, while Plus can view all retained snapshots.

## 5. Suggested Implementation Plan

1. Define the product contract first: free group cap, Plus group cap, exact cosmetic rules, berry multiplier behavior, and free history window.
2. Add subscription state and capability modeling:
   - New Swift files: `pico/PicoPlusEntitlements.swift`, `pico/PicoPlusService.swift`, `pico/PicoPlusStore.swift`.
   - Inject the store from `AppShellView` in `pico/ContentView.swift`.
3. Add backend entitlement storage and enforcement:
   - New Supabase migration for subscription/entitlement tables or columns.
   - Add helper SQL functions like `user_has_pico_plus(user_id uuid)` and capability helpers for group limits/history windows/reward multipliers.
4. Wire SuperwallKit through the new service/store:
   - Configure SDK at launch in `pico/picoApp.swift` or from the subscription service initialization path.
   - Trigger paywalls from reusable gate methods rather than feature views calling Superwall directly.
5. Implement gates feature by feature:
   - Group sessions: client selection limits plus RPC enforcement in `invite_focus_session_members`.
   - Cosmetics: inventory grants or entitlement-aware store/profile checks.
   - Friend cosmetics: explicit model after product decision.
   - Berry gain: server-side reward/sale multiplier plus client copy/analytics.
   - Calendar/history: UI navigation restrictions plus RPC restrictions.
6. Add tests/mocks where possible:
   - Swift store/service unit tests for capability decisions.
   - Supabase SQL tests or at least `supabase db lint` plus manual RPC checks for free vs Plus users.

## 6. Risks and Edge Cases

- Client-only gating is insufficient. Users can call Supabase RPCs directly with a valid token, so group limits, history limits, paid item grants, and reward multipliers need backend checks.
- Subscription source of truth can drift. Superwall/local purchase state, Supabase entitlement state, and app cache need a clear sync strategy for offline, restore purchase, expiration, refund, and cross-device cases.
- Existing `store_items.is_paid_only` is not enough by itself. It blocks berry purchase, but there is no current path to grant paid-only items to active subscribers.
- Inventory and profile ownership are coupled. `AuthSessionStore` and `BerryStore` both track owned store item IDs; `StorePage` currently applies `sessionStore.ownedStoreItemIDs` after loading BerryStore inventory.
- Group sessions have concurrency hazards. Multiple invites, joins, and starts can happen around the same time, so server group-limit checks should count joined plus invited members inside the locked transaction.
- Existing multiplayer completion logic is sensitive. `FocusStore` has optimistic result persistence/retry and realtime refresh; changing rewards or group rules must not break pending result sync.
- Calendar history requires both activity and detail gating. If only the month activity call is gated, users might still fetch old days through `fetch_daily_village_snapshot`.
- Friend scarf gating could confuse bond progression. Bond-level scarves currently communicate friendship progress; hiding or paywalling them directly may change the meaning of bonds.
- The repo currently has unrelated dirty/untracked files (`pico/FocusStore.swift` and a temporary focus-duration migration). Future implementation should inspect diffs before editing those files.

## 7. Files Likely To Change

- New app files:
  - `pico/PicoPlusEntitlements.swift`
  - `pico/PicoPlusService.swift`
  - `pico/PicoPlusStore.swift`
- App composition/auth:
  - `pico/picoApp.swift`
  - `pico/ContentView.swift`
  - `pico/AuthSessionStore.swift`
  - `pico/AuthService.swift`
- Focus/group sessions:
  - `pico/FocusStore.swift`
  - `pico/FocusService.swift`
  - `pico/FocusRealtimeService.swift` only if entitlement-related realtime refresh is needed.
- Store/avatar/cosmetics:
  - `pico/BerryStore.swift`
  - `pico/BerryService.swift`
  - `pico/AvatarCatalog.swift`
  - `pico/VillageStore.swift`
  - `pico/VillageViews.swift`
  - `pico/FriendViews.swift`
- Daily history:
  - `pico/DailySnapshotService.swift`
  - `pico/ContentView.swift`
- Analytics:
  - `pico/AnalyticsEvent.swift`
  - `pico/AnalyticsService.swift`
  - possibly new `pico/AnalyticsEvents+PicoPlus.swift`
- Supabase:
  - new migration under `supabase/migrations/`
  - existing RPC definitions in `supabase/migrations/20260513090000_init_clean_schema.sql` as reference for new migrations that replace/extend functions.
- Project/dependencies if Superwall configuration changes:
  - `pico.xcodeproj/project.pbxproj`
  - `pico.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
