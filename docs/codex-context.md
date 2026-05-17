# Codex Context

This document summarizes the codebase from direct inspection. Paths are cited with line numbers where useful. Items marked unclear were not inferable from the current source alone.

## App Architecture Overview

- This is a SwiftUI iOS app. The app entry point is `pico/picoApp.swift:11`, which configures Firebase, Google Sign-In, segmented-control appearance, and navigation-bar appearance before presenting `ContentView`.
- `ContentView` immediately delegates to `AuthGateView` and applies global foreground, tint, and navigation-bar color styling (`pico/ContentView.swift:13`, `pico/ContentView.swift:16`).
- Auth gating is centralized in `AuthGateView`: it owns a `@StateObject AuthSessionStore`, restores the session in a `.task`, shows a loading screen during restore, routes signed-out users to auth/onboarding, and routes signed-in users to `AppShellView` (`pico/AuthViews.swift:12`, `pico/AuthViews.swift:16`, `pico/AuthViews.swift:30`).
- `AppShellView` is the main composition root after login. It owns app-wide stores as `@StateObject`s and injects them as environment objects: `FriendStore`, `FocusStore`, `VillageStore`, `BondRewardClaimStore`, `BerryStore`, `FishStore`, and `IslandStore` (`pico/ContentView.swift:22`, `pico/ContentView.swift:28`, `pico/ContentView.swift:87`).
- The architecture is mostly “view + store + service” rather than folderized modules. Most Swift files live directly under `pico/`; `ContentView.swift` is very large and contains Home, Bonds, Fishing, Store, Profile, daily snapshot, and focus-sheet UI (`pico/ContentView.swift` is 9,127 lines per `wc -l`).
- Swift Package dependencies include Supabase, FirebaseAnalytics, GoogleSignIn, and SuperwallKit in the Xcode project (`pico.xcodeproj/project.pbxproj:134`, `pico.xcodeproj/project.pbxproj:436`). Superwall paywall access is centralized through `PicoPlusService` and `PicoPlusStore`.

## Main Feature Modules And Locations

- Auth/session:
  - `pico/AuthViews.swift` contains `AuthGateView`, route-driven auth root, login, signup options, and signup flow (`pico/AuthViews.swift:12`, `pico/AuthViews.swift:36`, `pico/AuthViews.swift:307`, `pico/AuthViews.swift:497`).
  - `pico/AuthSessionStore.swift` owns session/profile state and profile inventory ownership (`pico/AuthSessionStore.swift:12`, `pico/AuthSessionStore.swift:13`).
  - `pico/AuthService.swift` wraps Supabase auth, profile REST calls, inventory fetch for auth ownership, and legacy keychain session migration (`pico/AuthService.swift:102`, `pico/AuthService.swift:132`, `pico/AuthService.swift:287`, `pico/AuthService.swift:493`).
  - `pico/UsernameRules.swift` centralizes user-chosen username validation. Generated OAuth fallback usernames matching `pico_[0-9a-f]{19}` are reserved and must not be accepted as completed usernames.
  - OAuth sign-in must not prefill profile-completion fields. The client does not request/use Apple full names or Google display names for profile completion, and `handle_new_auth_user` must not copy OAuth `full_name`, `name`, or email prefix into `public.user_profiles.display_name`.
  - OAuth profile completion requires a user-entered display name followed by a user-entered username. The fields are never prefilled, and the client saves both only after the final username step succeeds.
- Onboarding:
  - `pico/OnboardingViews.swift` contains `OnboardingSequenceView`, onboarding state, analytics, and visual components (`pico/OnboardingViews.swift:162`, `pico/OnboardingViews.swift:598`).
  - Ordered onboarding steps run from welcome through auth handoff (`pico/OnboardingViews.swift:615`).
- Main shell and home:
  - `pico/ContentView.swift` contains `AppShellView`, `PicoSideNavigation`, `AppTab`, `HomePage`, focus result overlay, daily snapshots, and bottom-bar focus launch (`pico/ContentView.swift:22`, `pico/ContentView.swift:504`, `pico/ContentView.swift:599`, `pico/ContentView.swift:676`).
- Focus:
  - `pico/FocusStore.swift` owns lobby/active/result session state, invites, optimistic completion/interruption, local pending result persistence, background interruption handling, and realtime subscription setup (`pico/FocusStore.swift:53`, `pico/FocusStore.swift:59`, `pico/FocusStore.swift:770`, `pico/FocusStore.swift:968`).
  - `pico/FocusService.swift` defines focus models and calls Supabase RPC endpoints for session lifecycle operations (`pico/FocusService.swift:10`, `pico/FocusService.swift:185`, `pico/FocusService.swift:202`, `pico/FocusService.swift:264`).
  - `pico/FocusRealtimeService.swift` subscribes to Supabase realtime changes for focus sessions, members, events, or invite membership (`pico/FocusRealtimeService.swift:11`, `pico/FocusRealtimeService.swift:37`).
  - `pico/FocusViews.swift` has a `FocusPage`, but it appears unused by the current app shell; only its preview references `FocusPage()` (`pico/FocusViews.swift:11`, `pico/FocusViews.swift:667`, `pico/ContentView.swift:599`).
- Social/friends/bonds:
  - `pico/FriendViews.swift` contains `FriendsPage`, add-friend search, incoming requests, friend profile, reusable profile search list, and friend cards (`pico/FriendViews.swift:10`, `pico/FriendViews.swift:126`, `pico/FriendViews.swift:211`, `pico/FriendViews.swift:268`, `pico/FriendViews.swift:386`).
  - `pico/FriendStore.swift` owns friend lists, incoming requests, search state, active request/unfriend IDs, and notices (`pico/FriendStore.swift:12`, `pico/FriendStore.swift:13`).
  - `pico/FriendService.swift` uses REST/RPC calls for profile search, friend requests, listing friends, and unfriending (`pico/FriendService.swift:50`, `pico/FriendService.swift:88`, `pico/FriendService.swift:126`, `pico/FriendService.swift:137`).
  - Bond UI lives in `ContentView.swift` as `BondsContent` and related rows/sheets (`pico/ContentView.swift:1643`, `pico/ContentView.swift:1836`, `pico/ContentView.swift:2232`).
  - Bond scarf thresholds are level 2 at 3 pair sessions, level 3 at 6, level 4 at 9, and level 5 at 12. Keep `BondScarfMilestone` and the SQL `villager_bond_level` function aligned.
- Village/island:
  - `pico/VillageViews.swift` contains `VillageView`, SpriteKit bridge, map styles, scene, tile, and villager node code (`pico/VillageViews.swift:12`, `pico/VillageViews.swift:65`, `pico/VillageViews.swift:121`, `pico/VillageViews.swift:267`).
  - `pico/VillageStore.swift` owns residents and load state; `BondRewardClaimStore` persists locally claimed bond levels in caches (`pico/VillageStore.swift:19`, `pico/VillageStore.swift:113`).
  - `pico/VillageService.swift` fetches village residents through `list_village_residents` (`pico/VillageService.swift:69`).
  - `pico/IslandStore.swift` defines `PicoIsland` and persists per-user island selection in `UserDefaults` (`pico/IslandStore.swift:11`, `pico/IslandStore.swift:82`, `pico/IslandStore.swift:137`).
- Fishing/store/economy:
  - `FishingPage`, collection/inventory/island selector UI, and fish visual components are in `ContentView.swift` (`pico/ContentView.swift:5568`, `pico/ContentView.swift:6479`).
  - `StorePage`, buy/sell mode, island/hat previews, and fish selling UI are in `ContentView.swift` (`pico/ContentView.swift:6691`, `pico/ContentView.swift:7039`, `pico/ContentView.swift:7356`).
  - `pico/FishStore.swift` caches session catches, inventory, catalog by island, collection counts, and inventory counts (`pico/FishStore.swift:12`, `pico/FishStore.swift:13`).
  - `pico/FishService.swift` defines fish models and calls REST/RPC endpoints for catches, catalogs, counts, and selling (`pico/FishService.swift:10`, `pico/FishService.swift:301`, `pico/FishService.swift:318`, `pico/FishService.swift:371`).
  - `pico/BerryStore.swift` owns berry balance, store catalog, inventory, and purchase state (`pico/BerryStore.swift:12`).
  - `pico/BerryService.swift` calls RPC endpoints for berries, store catalog, inventory, and purchase (`pico/BerryService.swift:100`, `pico/BerryService.swift:111`, `pico/BerryService.swift:129`, `pico/BerryService.swift:140`).
- Pico Plus:
  - `pico/PicoPlusStore.swift` owns server-backed entitlement state and exposes a `PicoPlusCapabilities` value for feature checks such as historical snapshots, bond rewards, group invite limits, paid-only store item purchases, and fish sale multiplier. Feature views should prefer capability methods/properties over raw Plus-status checks. Active Plus removes the multiplayer group-size cap.
  - `pico/PicoPlusService.swift` wraps entitlement fetches and Superwall paywall presentation.
  - Paywall presentation is centralized through `PicoPlusStore.presentPaywall(source:authSession:)`; feature views should pass a `PicoPlusPaywallSource` with an explicit `PicoPlusPlacement` rather than calling Superwall placements directly. The shared CTA is `PicoPlusCTAButton` in `pico/PicoPlusPaywallView.swift`.
  - Active Plus unlocks the ability to purchase Plus-exclusive cosmetics with berries through the regular `purchase_store_item` path. Purchased cosmetics remain usable after subscription expiration, and profile hat ownership continues to flow through `AuthSessionStore.ownedStoreItemIDs`.
  - Active Plus also gives a 3x fish sale berry multiplier. The store UI reads `PicoPlusCapabilities.fishSaleBerryMultiplier`, but `sell_user_fish` is authoritative and computes the credited amount from `public.user_has_pico_plus(auth.uid())` at sale time.
  - Bond scarf rendering must use claimed reward level plus `PicoPlusCapabilities.visibleBondRewardLevel(...)`, not raw `VillageResident.bondLevel`. Free users should never render bond scarf rewards above the free level even if the underlying bond level is higher or stale local claims exist.
- Avatar/assets:
  - `pico/AvatarCatalog.swift` defines `AvatarConfig`, hats, scarves, SpriteKit layering, avatar badge, and picker (`pico/AvatarCatalog.swift:12`, `pico/AvatarCatalog.swift:78`, `pico/AvatarCatalog.swift:154`, `pico/AvatarCatalog.swift:496`, `pico/AvatarCatalog.swift:646`).
  - Sprite atlases live under `pico/Atlases/`; icons live under `pico/Assets.xcassets/` and `pico/Icons/`.
- Analytics:
  - Typed analytics primitives and event catalog live in `pico/AnalyticsEvent.swift`. Feature-facing code uses `AnalyticsEventID`, `AnalyticsParameterKey`, and `AnalyticsValue` rather than raw Firebase names or `[String: Any]` payloads.
  - `pico/FirebaseAnalyticsEngine.swift` is the only Firebase event adapter. It validates events against `AnalyticsCatalog`, appends common parameters, converts typed values to Firebase parameters, and calls `FirebaseAnalytics.Analytics.logEvent`.
  - `pico/Analytics.swift` is the central entry point for tracking and user property support. Onboarding and signup funnel helpers live in `pico/OnboardingAnalytics.swift`.

## Navigation Flow

- Launch flow: `picoApp` -> `ContentView` -> `AuthGateView` (`pico/picoApp.swift:25`, `pico/ContentView.swift:13`, `pico/AuthViews.swift:12`).
- Signed-out flow: `AuthRootView` uses an internal `AuthRoute` enum with `.entry`, `.onboarding`, `.login`, `.signupOptions`, and `.signup` (`pico/AuthViews.swift:36`, `pico/AuthViews.swift:149`).
- Onboarding handoff: `OnboardingSequenceView` advances through `OnboardingStep.ordered`; completing the last step calls `onSignup(normalizedDisplayName)` (`pico/OnboardingViews.swift:520`, `pico/OnboardingViews.swift:615`).
- Signed-in flow: `AppShellView` selects among `AppTab` cases `home`, `fishing`, `store`, `friends`, and `settings` (`pico/ContentView.swift:599`).
- Main navigation is adaptive:
  - Compact horizontal size uses a drawer overlay (`pico/ContentView.swift:41`, `pico/ContentView.swift:55`, `pico/ContentView.swift:205`).
  - Non-compact size uses a persistent side navigation rail (`pico/ContentView.swift:44`).
  - Each selected tab is embedded in a `NavigationStack` (`pico/ContentView.swift:209`).
- Tab roots are mapped in `AppTab.rootView`: Island/Home, Fishing, Store, Social/Friends, Profile (`pico/ContentView.swift:651`).
- Secondary navigation exists inside feature pages through `NavigationLink`s, for example Add Friend and Incoming Requests from `FriendsPage` (`pico/FriendViews.swift:20`, `pico/FriendViews.swift:31`).
- Focus is launched from the Home bottom bar, not as a top-level tab. `HomePage` presents `StartFocusSheet`, daily snapshot calendar, and fish reveal as sheets/full-screen covers (`pico/ContentView.swift:723`, `pico/ContentView.swift:761`, `pico/ContentView.swift:773`, `pico/ContentView.swift:781`).

## State Management Patterns

- Long-lived app state uses `@MainActor final class ...: ObservableObject` with `@Published` properties in stores (`pico/AuthSessionStore.swift:11`, `pico/FocusStore.swift:52`, `pico/FriendStore.swift:11`, `pico/FishStore.swift:11`, `pico/BerryStore.swift:11`, `pico/VillageStore.swift:18`, `pico/IslandStore.swift:81`).
- `AuthGateView` owns `AuthSessionStore`; `AppShellView` owns post-auth stores and injects them into the environment (`pico/AuthViews.swift:13`, `pico/ContentView.swift:28`, `pico/ContentView.swift:87`).
- Views use local `@State` for transient UI state: selected tab/drawer state in `AppShellView`, focus sheet state in `HomePage`, selected fishing/store modes, profile drafts, etc. (`pico/ContentView.swift:26`, `pico/ContentView.swift:687`, `pico/ContentView.swift:5574`, `pico/ContentView.swift:6696`, `pico/ContentView.swift:8242`).
- Async loads are primarily triggered from SwiftUI `.task`, `.task(id:)`, `.refreshable`, `.onChange`, and `NotificationCenter`/scene phase handlers (`pico/ContentView.swift:94`, `pico/ContentView.swift:118`, `pico/ContentView.swift:173`, `pico/ContentView.swift:191`, `pico/FriendViews.swift:68`, `pico/ContentView.swift:5699`).
- Stores usually guard concurrent work with boolean flags or active IDs, then set notices from localized errors (`pico/FriendStore.swift:34`, `pico/FriendStore.swift:127`, `pico/BerryStore.swift:32`, `pico/FishStore.swift:70`, `pico/FocusStore.swift:171`).
- Local persistence:
  - `FocusStore` saves open/pending focus state to `UserDefaults` under `pico.focus.saved-state.v4` and replays pending completions/interruptions (`pico/FocusStore.swift:79`, `pico/FocusStore.swift:104`, `pico/FocusStore.swift:1004`).
  - `IslandStore` persists selected island per user in `UserDefaults` (`pico/IslandStore.swift:85`, `pico/IslandStore.swift:137`).
  - `BondRewardClaimStore` persists claimed bond levels to `bond-reward-claims.json` in caches (`pico/VillageStore.swift:116`, `pico/VillageStore.swift:153`).
  - `AuthService` can migrate a legacy keychain session into Supabase auth (`pico/AuthService.swift:493`, `pico/AuthService.swift:525`).

## Data/API/Supabase Usage Patterns

- Supabase configuration is hardcoded in `pico/SupabaseConfig.swift` with a project URL and anon key; `isConfigured` checks for placeholders and empty values (`pico/SupabaseConfig.swift:10`, `pico/SupabaseConfig.swift:18`).
- Auth uses the Supabase Swift SDK for signup, email/password signin, Apple ID token signin, Google ID token signin, session restore, signout, and auth state changes (`pico/AuthService.swift:109`, `pico/AuthService.swift:154`, `pico/AuthService.swift:187`, `pico/AuthService.swift:204`, `pico/AuthService.swift:224`, `pico/AuthService.swift:266`).
- Most non-auth data access uses manual `URLSession` calls against PostgREST/RPC paths. Services set `apikey`, `Authorization: Bearer <token>`, and JSON headers, then decode with `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` and encode with `.convertToSnakeCase` (`pico/AuthService.swift:123`, `pico/AuthService.swift:434`, `pico/FocusService.swift:193`, `pico/FocusService.swift:412`, `pico/BerryService.swift:91`, `pico/FishService.swift:309`, `pico/VillageService.swift:60`, `pico/FriendService.swift:41`).
- Error handling is duplicated per service with service-specific `LocalizedError` enums and per-service Supabase error response structs (`pico/AuthService.swift:76`, `pico/FocusService.swift:168`, `pico/FriendService.swift:16`, `pico/BerryService.swift:66`, `pico/FishService.swift:284`, `pico/VillageService.swift:35`).
- RPC-heavy domains:
  - Focus: `create_focus_session`, `update_focus_session_config`, `fetch_focus_session_detail`, `fetch_current_focus_session_detail`, `list_incoming_focus_session_invites`, `sync_open_focus_sessions`, `join_focus_session`, `start_focus_session`, `complete_focus_session`, `interrupt_focus_session`, etc. (`pico/FocusService.swift:208`, `pico/FocusService.swift:224`, `pico/FocusService.swift:249`, `pico/FocusService.swift:264`, `pico/FocusService.swift:275`, `pico/FocusService.swift:286`, `pico/FocusService.swift:297`, `pico/FocusService.swift:328`, `pico/FocusService.swift:336`, `pico/FocusService.swift:352`).
  - Friends: `send_friend_request`, `list_incoming_friend_requests`, `accept_friend_request`, `reject_friend_request`, `list_friends`, `unfriend_user` (`pico/FriendService.swift:88`, `pico/FriendService.swift:97`, `pico/FriendService.swift:108`, `pico/FriendService.swift:117`, `pico/FriendService.swift:126`, `pico/FriendService.swift:137`).
  - Store/berries: `fetch_user_berries`, `fetch_store_catalog`, `fetch_user_store_inventory`, `purchase_store_item` (`pico/BerryService.swift:100`, `pico/BerryService.swift:111`, `pico/BerryService.swift:129`, `pico/BerryService.swift:140`).
  - Pico Plus: `fetch_pico_plus_entitlement` returns active entitlement state, `invite_focus_session_members` gates groups above the free member limit behind Plus without capping Plus groups, and `purchase_store_item` requires active Plus before allowing paid-only store item purchases.
  - Daily snapshots: `fetch_daily_village_snapshot` and `list_daily_focus_activity` (`pico/DailySnapshotService.swift:124`, `pico/DailySnapshotService.swift:138`).
- Direct table reads exist for `user_profiles`, `user_fish_catches`, and `island_sea_critters` (`pico/AuthService.swift:292`, `pico/FriendService.swift:51`, `pico/FishService.swift:318`, `pico/FishService.swift:386`).
- `public.user_profiles.profile_completed_at` is the backend authority for whether a profile may be socially discoverable. OAuth-created fallback profiles start with `profile_completed_at = null`; RLS only lets authenticated users read their own incomplete profile or completed public profiles, and friend lookup/request paths filter or reject incomplete profiles.
- Supabase schema/migrations are under `supabase/migrations/`. The initial migration creates users, profiles, sea critters, islands, friendships, focus sessions, session members/events, villages/bonds, berry balances, store inventory, fish catches, daily snapshots, and RLS policies (`supabase/migrations/20260513090000_init_clean_schema.sql:40`, `supabase/migrations/20260513090000_init_clean_schema.sql:157`, `supabase/migrations/20260513090000_init_clean_schema.sql:338`, `supabase/migrations/20260513090000_init_clean_schema.sql:368`, `supabase/migrations/20260513090000_init_clean_schema.sql:503`, `supabase/migrations/20260513090000_init_clean_schema.sql:602`, `supabase/migrations/20260513090000_init_clean_schema.sql:674`, `supabase/migrations/20260513090000_init_clean_schema.sql:897`, `supabase/migrations/20260513090000_init_clean_schema.sql:3608`).
- Realtime is limited to focus state/invite changes; it watches `focus_sessions`, `session_members`, and `session_events` for a session, or `session_members` for invite membership (`pico/FocusRealtimeService.swift:43`, `pico/FocusRealtimeService.swift:64`).

## Styling/Theme Conventions

- Central design tokens live in `pico/PicoDesignSystem.swift`: colors, spacing, radii, typography, shadows, icon assets, card modifiers, button styles, and UIKit appearance wrappers (`pico/PicoDesignSystem.swift:16`, `pico/PicoDesignSystem.swift:80`, `pico/PicoDesignSystem.swift:91`, `pico/PicoDesignSystem.swift:100`, `pico/PicoDesignSystem.swift:215`, `pico/PicoDesignSystem.swift:234`).
- The dominant palette is warm cream background/surfaces with green primary and selected accents: `appBackground = 0xFAF8F2`, `surface = white`, `softSurface = 0xF1EDE4`, `primary = 0x7BAE3B` (`pico/PicoDesignSystem.swift:22`, `pico/PicoDesignSystem.swift:26`).
- Typography uses custom Quicksand for primary/display text and Spline Sans for secondary/body text, registered from bundled OTF font directories (`pico/PicoDesignSystem.swift:130`, `pico/PicoDesignSystem.swift:135`, `pico/PicoDesignSystem.swift:177`).
- Common style modifiers are `.picoCard`, `.picoCreamCard`, and `.picoScreenBackground` (`pico/PicoDesignSystem.swift:423`).
- Buttons use custom `ButtonStyle`s such as `PicoPrimaryButtonStyle`, `PicoSecondaryButtonStyle`, `PicoCreamBorderedButtonStyle`, and `PicoDestructiveButtonStyle` (`pico/PicoDesignSystem.swift:454`, `pico/PicoDesignSystem.swift:473`, `pico/PicoDesignSystem.swift:485`, `pico/PicoDesignSystem.swift:506`).
- Icons are mostly template-rendered asset catalog SVGs through `PicoIcon` and `PicoIconAsset`; Fishing uses SF Symbol `fish` in the tab icon (`pico/PicoDesignSystem.swift:264`, `pico/ContentView.swift:623`).
- SpriteKit is used for avatar/village scenes, with SwiftUI bridges through `UIViewRepresentable` (`pico/VillageViews.swift:121`, `pico/AvatarCatalog.swift:496`, `pico/ContentView.swift:8428`).

## Existing Reusable Components

- Design system: `PicoIcon`, card modifiers, card divider, screen background, and button styles (`pico/PicoDesignSystem.swift:264`, `pico/PicoDesignSystem.swift:367`, `pico/PicoDesignSystem.swift:394`, `pico/PicoDesignSystem.swift:405`, `pico/PicoDesignSystem.swift:423`, `pico/PicoDesignSystem.swift:454`).
- Shell/navigation: `PicoSideNavigation`, `PicoScreenTopBar`, and `PicoNavigationMenuButton` (`pico/ContentView.swift:504`, `pico/ContentView.swift:1579`, `pico/ContentView.swift:1605`).
- Auth: `PicoAuthDivider`, `PicoGoogleSignInButton`, and `PicoAppleSignInButton` (`pico/GoogleSignInButtonView.swift:15`, `pico/GoogleSignInButtonView.swift:36`, `pico/GoogleSignInButtonView.swift:130`).
- Avatar: `AvatarBadgeView`, `AvatarPickerView`, layered SpriteKit avatar nodes, and profile avatar preview components (`pico/AvatarCatalog.swift:646`, `pico/AvatarCatalog.swift:686`, `pico/AvatarCatalog.swift:496`, `pico/ContentView.swift:8407`).
- Social: `UserProfileSearchList`, `FriendProfileRowView`, `FriendNoticeCard`, and friend request/list cards (`pico/FriendViews.swift:386`, `pico/FriendViews.swift:355`, `pico/FriendViews.swift:776`, `pico/FriendViews.swift:596`, `pico/FriendViews.swift:625`).
- Focus/home: `StartFocusSheet`, focus duration slider/range slider, active timer strip, focus completion overlay/card, and fish catch reveal (`pico/ContentView.swift:3621`, `pico/ContentView.swift:4279`, `pico/ContentView.swift:4309`, `pico/ContentView.swift:4831`, `pico/ContentView.swift:4888`, `pico/ContentView.swift:1047`).
- Store/fishing: fish inventory/collection rows, store item rows, island/hat preview overlays, and berry labels (`pico/ContentView.swift:5884`, `pico/ContentView.swift:6479`, `pico/ContentView.swift:7447`, `pico/ContentView.swift:7607`, `pico/ContentView.swift:7966`, `pico/ContentView.swift:5548`).

## Known Risks Or Confusing Areas

- `ContentView.swift` is a large multi-feature file. Any edit there risks unintended cross-feature side effects because Home, Focus sheets, Fishing, Store, Bonds, Profile, and reusable components are colocated (`pico/ContentView.swift` is 9,127 lines).
- `FocusViews.swift` and `VillagePage` appear unused by the current tab shell except previews; focus and village UI are mainly embedded in `ContentView.swift`/`HomePage` now. Treat them as possibly legacy until confirmed (`pico/FocusViews.swift:11`, `pico/FocusViews.swift:667`, `pico/VillageViews.swift:23`, `pico/VillageViews.swift:1236`, `pico/ContentView.swift:651`).
- Focus minimum duration is currently a temporary 10-second override in Swift and an untracked migration also appears to lower the DB constraint/RPC check. The comment says to restore to 10 minutes after testing (`pico/FocusStore.swift:55`, `supabase/migrations/20260515090000_temporarily_allow_10_second_focus_sessions.sql:1`). This repo had that migration untracked at inspection time.
- The worktree was already dirty before this document was created: `pico/FocusStore.swift` modified and `supabase/migrations/20260515090000_temporarily_allow_10_second_focus_sessions.sql` untracked. Do not revert or assume ownership of those changes.
- Supabase request code is repeated across services. Changing auth headers, decoding, or error behavior in one service will not automatically update others (`pico/AuthService.swift:419`, `pico/FocusService.swift:432`, `pico/FriendService.swift:175`, `pico/BerryService.swift:178`, `pico/FishService.swift:432`, `pico/VillageService.swift:95`).
- `SupabaseConfig.swift` contains a real-looking project URL and anon key in source. It may be intentional for anon/mobile clients, but secret/config policy is unclear (`pico/SupabaseConfig.swift:10`).
- `StorePage` now syncs successfully fetched `BerryStore` inventory IDs back into `AuthSessionStore`, then falls back to auth-owned IDs only if the store inventory fetch did not produce a fresh result. This keeps profile hat validation aligned after store purchases, including Pico Plus-exclusive cosmetic purchases.
- Pico Plus cosmetics are not free subscription grants. Plus users can buy paid-only items with berries, and those purchased inventory rows remain usable after subscription expiration.
- `AuthService.isUsernameAvailable` uses the narrow `is_username_available` RPC with the anon key. Anonymous direct `user_profiles` reads and anonymous `is_email_available` execution are intentionally revoked to reduce signup scraping and email enumeration.
- `FriendService.searchProfiles` manually sanitizes query text and builds an `ilike` pattern in a URL query item (`pico/FriendService.swift:60`). It filters for completed profiles, but search semantics and escaping behavior should be considered before extending it.
- `FishID.assetName` contains fallback mappings for older/alternate fish IDs to freshwater/saltwater assets, which may hide data mismatches between DB IDs and bundled assets (`pico/FishService.swift:39`).
- Several async side effects are coordinated in `AppShellView` via `.onChange`, scene phase, protected-data notifications, and store callbacks. Focus completion triggers village/berry/fish reloads from the shell (`pico/ContentView.swift:94`, `pico/ContentView.swift:134`, `pico/ContentView.swift:173`, `pico/ContentView.swift:191`).
- Database schema is large and function-heavy in a single initial migration. Before changing client payloads, inspect the relevant RPC function definitions in `supabase/migrations/20260513090000_init_clean_schema.sql`.

## Recommended Implementation Rules For Future Codex Tasks

- Read the affected store, service, view, and migration/RPC together before editing. UI behavior commonly depends on store flags and RPC response shapes.
- Preserve the current store/service split: views call stores; stores call services; services own HTTP/Supabase decoding and request structs.
- Keep new long-lived UI/data state in `@MainActor ObservableObject` stores when it is shared across views; keep sheet/form/selection state local with `@State` when it is view-only.
- Use existing design tokens and components from `PicoDesignSystem.swift`; do not introduce ad hoc colors, fonts, card styles, or button styling unless there is a strong local precedent.
- For Supabase changes, update both Swift request/response types and SQL migrations/RPCs together, then verify RLS and response decoding. Most service decoders expect snake_case from PostgREST converted to Swift camelCase.
- For profile/social changes, preserve the privacy boundary that incomplete OAuth profiles are only readable by their owner and are never friend-searchable or friend-requestable. Update `profile_completed_at` handling, RLS, `send_friend_request`, and client filters together.
- Do not reintroduce OAuth profile prefill. Google/Apple identity names and email local-parts are private auth data until the user explicitly types their public username/display name.
- For focus changes, account for optimistic local results, pending result retry, realtime refresh, app background interruption, and scene/protected-data transitions. The happy path is not enough.
- For island/fish/store changes, keep `PicoIsland.backendID`, store item `itemKey`, `island_sea_critters.island_id`, and fish catalog/cache keys aligned.
- For avatar/hat/store ownership changes, update `StoreItem.avatarHat`, `AuthSessionStore.ownedHats`, and profile save validation together.
- Avoid broad refactors in `ContentView.swift` during feature work unless the task explicitly calls for it. Prefer small, localized edits and extract only when it reduces immediate risk.
- Before modifying files with existing uncommitted changes, inspect the diff and preserve user work.
- Mark unclear areas in future docs or implementation notes rather than inferring intent from names alone.
