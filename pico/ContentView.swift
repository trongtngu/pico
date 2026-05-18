//
//  ContentView.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

import SpriteKit
import SwiftUI
import UIKit
import Combine

struct ContentView: View {
    var body: some View {
        AuthGateView()
            .foregroundStyle(PicoColors.textPrimary)
            .tint(PicoColors.primary)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

struct AppShellView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @State private var selectedTab: AppTab = .home
    @State private var isNavigationDrawerOpen = false
    @StateObject private var friendStore = FriendStore()
    @StateObject private var focusStore = FocusStore()
    @StateObject private var villageStore = VillageStore()
    @StateObject private var bondRewardClaimStore = BondRewardClaimStore()
    @StateObject private var berryStore = BerryStore()
    @StateObject private var fishStore = FishStore()
    @StateObject private var islandStore = IslandStore()
    @StateObject private var picoPlusStore = PicoPlusStore()

    var body: some View {
        ZStack {
            PicoColors.appBackground
                .ignoresSafeArea()

            if usesDrawerNavigation {
                navigationContent
            } else {
                HStack(spacing: 0) {
                    PicoSideNavigation(
                        selectedTab: selectedTab,
                        isPersistent: true,
                        onSelect: selectTab
                    )

                    navigationContent
                }
            }

            if usesDrawerNavigation && isNavigationDrawerOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isNavigationDrawerOpen = false
                    }

                HStack(spacing: 0) {
                    PicoSideNavigation(
                        selectedTab: selectedTab,
                        isPersistent: false,
                        onSelect: selectTab
                    )

                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .leading))
            }

            if let profile = sessionStore.profile, profile.requiresProfileCompletion {
                ProfileCompletionView(profile: profile)
                    .zIndex(20)
            } else if sessionStore.profile == nil, sessionStore.isProfileLoading {
                ProgressView()
                    .tint(PicoColors.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PicoColors.appBackground)
                    .zIndex(20)
            }
        }
        .animation(.snappy(duration: 0.22), value: isNavigationDrawerOpen)
        .tint(PicoColors.primary)
        .environmentObject(friendStore)
        .environmentObject(focusStore)
        .environmentObject(villageStore)
        .environmentObject(bondRewardClaimStore)
        .environmentObject(berryStore)
        .environmentObject(fishStore)
        .environmentObject(islandStore)
        .environmentObject(picoPlusStore)
        .task(id: sessionStore.session?.user?.id) {
            await sessionStore.refreshSessionIfNeeded()
            await sessionStore.loadProfileIfNeeded()
            picoPlusStore.configureIdentity(session: sessionStore.session, profile: sessionStore.profile)
            await picoPlusStore.refresh(for: sessionStore.session)
            await presentPendingOnboardingPlusPaywallIfNeeded()
            islandStore.configure(
                for: sessionStore.session?.user?.id,
                ownedIslandIDs: sessionStore.ownedIslandIDs
            )
            focusStore.updateSelectedIslandID(islandStore.selectedIslandID)
            await focusStore.restoreSavedState(for: sessionStore.session)
            if sessionStore.session == nil {
                villageStore.clear()
                berryStore.clear()
                fishStore.clear()
                focusStore.updateKnownVillageResidentIDs(nil)
            } else {
                await villageStore.loadResidents(for: sessionStore.session)
                focusStore.updateKnownVillageResidentIDs(currentVillageResidentIDs)
                await berryStore.loadBalance(for: sessionStore.session)
            }
        }
        .onChange(of: sessionStore.ownedIslandIDs) {
            islandStore.updateOwnedIslandIDs(sessionStore.ownedIslandIDs)
            focusStore.updateSelectedIslandID(islandStore.selectedIslandID)
        }
        .onChange(of: sessionStore.profile) {
            Task {
                picoPlusStore.configureIdentity(session: sessionStore.session, profile: sessionStore.profile)
                await presentPendingOnboardingPlusPaywallIfNeeded()
            }
        }
        .onChange(of: sessionStore.shouldPresentOnboardingPicoPlusPaywall) {
            Task {
                await presentPendingOnboardingPlusPaywallIfNeeded()
            }
        }
        .onChange(of: islandStore.selectedIsland) {
            focusStore.updateSelectedIslandID(islandStore.selectedIslandID)
            fishStore.prepareIslandFishData(islandID: islandStore.selectedIslandID)
            Task {
                await fishStore.loadFishCatalog(
                    for: sessionStore.session,
                    islandID: islandStore.selectedIslandID,
                    forceReload: true
                )
                await fishStore.loadCollectionCounts(
                    for: sessionStore.session,
                    islandID: islandStore.selectedIslandID,
                    forceReload: true
                )
            }
        }
        .onChange(of: focusStore.resultSession) {
            guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return }
            Task {
                await villageStore.loadResidents(for: sessionStore.session)
                await berryStore.loadBalance(for: sessionStore.session)
                if fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
                    await fishStore.loadFishCatalog(
                        for: sessionStore.session,
                        islandID: islandStore.selectedIslandID
                    )
                }
                await fishStore.loadSessionCatches(
                    sessionID: resultSession.id,
                    for: sessionStore.session,
                    retryIfEmpty: !focusStore.hasPendingResultSync
                )
            }
        }
        .onChange(of: focusStore.hasPendingResultSync) {
            guard !focusStore.hasPendingResultSync,
                  let resultSession = focusStore.resultSession,
                  resultSession.status == .completed else { return }
            Task {
                if fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
                    await fishStore.loadFishCatalog(
                        for: sessionStore.session,
                        islandID: islandStore.selectedIslandID
                    )
                }
                await fishStore.loadSessionCatches(
                    sessionID: resultSession.id,
                    for: sessionStore.session,
                    retryIfEmpty: true
                )
            }
        }
        .onChange(of: villageStore.residents) {
            focusStore.updateKnownVillageResidentIDs(currentVillageResidentIDs)
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task {
                    await sessionStore.refreshSessionIfNeeded()
                    picoPlusStore.configureIdentity(session: sessionStore.session, profile: sessionStore.profile)
                    await picoPlusStore.refresh(for: sessionStore.session)
                    await presentPendingOnboardingPlusPaywallIfNeeded()
                    await focusStore.handleSceneBecameActive(for: sessionStore.session)
                }
            case .background:
                focusStore.handleSceneMovedToBackground(
                    for: sessionStore.session,
                    protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
                )
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            focusStore.handleDeviceWillLock()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            Task {
                await focusStore.handleDeviceDidUnlock(for: sessionStore.session)
            }
        }
    }

    private var currentVillageResidentIDs: Set<UUID> {
        Set(villageStore.residents.map(\.profile.userID))
    }

    private var usesDrawerNavigation: Bool {
        horizontalSizeClass == .compact
    }

    private var navigationContent: some View {
        NavigationStack {
            selectedTab.rootView(openFocus: {
                selectTab(.home)
            }, openStore: {
                selectTab(.store)
            }, openNavigation: {
                isNavigationDrawerOpen = true
            }, usesDrawerNavigation: usesDrawerNavigation)
            .navigationTitle(usesDrawerNavigation ? "" : selectedTab.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
            .toolbar(usesDrawerNavigation ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if usesDrawerNavigation && selectedTab != .home {
                    PicoScreenTopBar(
                        title: selectedTab.title,
                        leading: {
                            PicoNavigationMenuButton(action: {
                                isNavigationDrawerOpen = true
                            })
                        },
                        trailing: {
                            Color.clear
                                .frame(width: 44, height: 44)
                        }
                    )
                }
            }
        }
    }

    private func selectTab(_ tab: AppTab) {
        selectedTab = tab
        isNavigationDrawerOpen = false

        if tab == .home {
            Task {
                await refreshHomeVillageData()
            }
        }
    }

    private func refreshHomeVillageData() async {
        await sessionStore.reloadProfile()
        await villageStore.loadResidents(for: sessionStore.session, force: true)
        focusStore.updateKnownVillageResidentIDs(currentVillageResidentIDs)
        await berryStore.loadBalance(for: sessionStore.session)
    }

    private func presentPendingOnboardingPlusPaywallIfNeeded() async {
        guard sessionStore.shouldPresentOnboardingPicoPlusPaywall,
              let session = sessionStore.session,
              let profile = sessionStore.profile,
              !profile.requiresProfileCompletion
        else {
            return
        }

        guard sessionStore.consumeOnboardingPicoPlusPaywallPending() else { return }

        picoPlusStore.configureIdentity(session: session, profile: profile)
        await picoPlusStore.refresh(for: session)

        guard !picoPlusStore.capabilities.isPlusActive else { return }

        await picoPlusStore.presentPaywall(
            source: .onboardingComplete(placement: .onboardingComplete),
            authSession: session
        )
    }
}

private struct ProfileCompletionView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    let profile: UserProfile

    @State private var currentStep: ProfileCompletionStep = .displayName
    @State private var displayName = ""
    @State private var username = ""

    private var currentIndex: Int {
        ProfileCompletionStep.ordered.firstIndex(of: currentStep) ?? 0
    }

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isDisplayNameValid: Bool {
        (1...40).contains(normalizedDisplayName.count)
    }

    private var isUsernameValid: Bool {
        PicoUsernameRules.isValidUserChosenUsername(normalizedUsername)
    }

    private var canContinue: Bool {
        guard !sessionStore.isLoading,
              !sessionStore.isProfileSaving
        else {
            return false
        }

        switch currentStep {
        case .displayName:
            return isDisplayNameValid
        case .username:
            return isUsernameValid
        }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                SignupProgressHeader(
                    currentIndex: currentIndex,
                    totalCount: ProfileCompletionStep.ordered.count,
                    showsBackButton: true,
                    onBack: goBack,
                    backAccessibilityLabel: "Sign out",
                    topInset: proxy.safeAreaInsets.top
                )

                VStack(spacing: PicoSpacing.section) {
                    VStack(spacing: PicoSpacing.compact) {
                        Text(currentStep.title)
                            .font(PicoTypography.sectionTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                            .multilineTextAlignment(.center)

                        if let subtitle = currentStep.subtitle {
                            Text(subtitle)
                                .font(PicoTypography.body)
                                .foregroundStyle(PicoColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    completionField

                    if let completionNotice {
                        ProfileNoticeCard(text: completionNotice)
                    }

                    Button {
                        Task {
                            await handlePrimaryAction()
                        }
                    } label: {
                        ZStack {
                            Text("Continue")
                                .frame(maxWidth: .infinity)

                            if sessionStore.isLoading || sessionStore.isProfileSaving {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(PicoColors.textOnPrimary)
                                }
                            }
                        }
                    }
                    .buttonStyle(PicoPrimaryButtonStyle())
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.62)

                    Spacer(minLength: PicoSpacing.largeSection)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.top, PicoSpacing.section)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .onAppear(perform: syncDrafts)
        .onChange(of: profile) {
            syncDrafts()
        }
    }

    @ViewBuilder
    private var completionField: some View {
        switch currentStep {
        case .displayName:
            TextField(
                "",
                text: $displayName,
                prompt: Text("Display name").foregroundStyle(PicoColors.textMuted)
            )
            .textContentType(.name)
            .submitLabel(.continue)
            .autocorrectionDisabled()
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onSubmit {
                guard canContinue else { return }

                Task {
                    await handlePrimaryAction()
                }
            }
            .onChange(of: displayName) {
                sessionStore.notice = nil
                sessionStore.clearProfileNotice()
            }
        case .username:
            TextField(
                "",
                text: $username,
                prompt: Text("Username").foregroundStyle(PicoColors.textMuted)
            )
            .textInputAutocapitalization(.never)
            .textContentType(.username)
            .submitLabel(.continue)
            .autocorrectionDisabled()
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onSubmit {
                guard canContinue else { return }

                Task {
                    await handlePrimaryAction()
                }
            }
            .onChange(of: username) {
                username = normalizedUsername
                sessionStore.notice = nil
                sessionStore.clearProfileNotice()
            }
        }
    }

    private var completionNotice: String? {
        sessionStore.profileNotice ?? sessionStore.notice
    }

    private func syncDrafts() {
        guard profile.requiresProfileCompletion else { return }

        currentStep = .displayName
        displayName = ""
        username = ""
        sessionStore.notice = nil
        sessionStore.clearProfileNotice()
    }

    private func goBack() {
        sessionStore.signOut()
    }

    private func handlePrimaryAction() async {
        guard canContinue else { return }

        switch currentStep {
        case .displayName:
            currentStep = .username
        case .username:
            let username = normalizedUsername
            guard await sessionStore.validateUsernameAvailability(username),
                  username == normalizedUsername
            else {
                return
            }

            await sessionStore.updateProfile(
                username: username,
                displayName: normalizedDisplayName,
                avatarConfig: profile.avatarConfig
            )
        }
    }
}

private enum ProfileCompletionStep: String, CaseIterable, Identifiable {
    case displayName
    case username

    static let ordered: [ProfileCompletionStep] = [
        .displayName,
        .username
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .displayName:
            "What's your first name?"
        case .username:
            "Choose a username"
        }
    }

    var subtitle: String? {
        switch self {
        case .displayName:
            nil
        case .username:
            "This is how friends will find you"
        }
    }
}

private extension UserProfile {
    var requiresProfileCompletion: Bool {
        profileCompletedAt == nil || PicoUsernameRules.isGeneratedOAuthUsername(username)
    }
}

private struct PicoSideNavigation: View {
    let selectedTab: AppTab
    let isPersistent: Bool
    let onSelect: (AppTab) -> Void

    private var width: CGFloat {
        isPersistent ? 84 : 286
    }

    private var horizontalPadding: CGFloat {
        isPersistent ? PicoSpacing.iconTextGap : PicoSpacing.standard
    }

    private var rowIconSize: CGFloat {
        isPersistent ? 25 : 26
    }

    private var rowIconFrameSize: CGFloat {
        32
    }

    private var rowContentSpacing: CGFloat {
        isPersistent ? 0 : PicoSpacing.standard
    }

    private var rowHorizontalPadding: CGFloat {
        isPersistent ? 0 : PicoSpacing.standard
    }

    private var rowWidth: CGFloat? {
        isPersistent ? 58 : nil
    }

    private var logoImage: UIImage? {
        [
            "Icons/pico_logo",
            "Icons/pico_logo.png",
            "pico_logo",
            "pico_logo.png"
        ]
        .lazy
        .compactMap { UIImage(named: $0) }
        .first
    }

    var body: some View {
        VStack(alignment: isPersistent ? .center : .leading, spacing: PicoSpacing.compact) {
            if !isPersistent {
                Group {
                    if let logoImage {
                        Image(uiImage: logoImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 42, alignment: .leading)
                    } else {
                        Text("Pico")
                            .font(PicoTypography.sectionTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                    }
                }
                .accessibilityLabel(Text("Pico"))
                .padding(.bottom, PicoSpacing.standard)
                .padding(.top, PicoSpacing.largeSection)
            }

            ForEach(AppTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    HStack(spacing: rowContentSpacing) {
                        tab.icon(isSelected: selectedTab == tab, size: rowIconSize)
                            .frame(width: rowIconFrameSize, height: rowIconFrameSize)

                        if !isPersistent {
                            Text(tab.title)
                                .font(PicoTypography.body.weight(.semibold))

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, rowHorizontalPadding)
                    .foregroundStyle(selectedTab == tab ? PicoColors.primary : PicoColors.textPrimary)
                    .frame(maxWidth: rowWidth ?? .infinity)
                    .frame(height: 56)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                                .fill(PicoColors.softSurface)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, isPersistent ? PicoSpacing.largeSection : 0)
        .padding(.bottom, PicoSpacing.standard)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(
            PicoColors.appBackground
                .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PicoColors.border)
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
        }
        .shadow(color: isPersistent ? .clear : Color.black.opacity(0.12), radius: 24, x: 8, y: 0)
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case home
    case fishing
    case store
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Island"
        case .fishing:
            "Fishing"
        case .store:
            "Store"
        case .friends:
            "Social"
        case .settings:
            "Profile"
        }
    }

    @ViewBuilder
    func icon(isSelected: Bool, size: CGFloat = 20) -> some View {
        switch self {
        case .fishing:
            Image(systemName: "fish")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        default:
            PicoIcon(iconAsset(isSelected: isSelected), size: size)
        }
    }

    private func iconAsset(isSelected: Bool) -> PicoIconAsset {
        switch self {
        case .home:
            isSelected ? .homeSolid : .homeRegular
        case .fishing:
            .sparklesRegular
        case .store:
            isSelected ? .buildingStorefrontSolid : .buildingStorefrontRegular
        case .friends:
            isSelected ? .usersSolid : .usersRegular
        case .settings:
            isSelected ? .userCircleSolid : .userCircleRegular
        }
    }

    @ViewBuilder
    func rootView(
        openFocus: @escaping () -> Void,
        openStore: @escaping () -> Void,
        openNavigation: @escaping () -> Void,
        usesDrawerNavigation: Bool
    ) -> some View {
        switch self {
        case .home:
            HomePage(
                showsMenuButton: usesDrawerNavigation,
                openNavigation: openNavigation
            )
        case .fishing:
            FishingPage(openStore: openStore)
        case .store:
            StorePage()
        case .friends:
            FriendsPage()
        case .settings:
            ProfilePage(openStore: openStore)
        }
    }
}

private struct HomePage: View {
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var berryStore: BerryStore
    @EnvironmentObject private var fishStore: FishStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var islandStore: IslandStore
    let showsMenuButton: Bool
    let openNavigation: () -> Void
    private let dailySnapshotService = DailySnapshotService()
    @State private var isStartFocusSheetPresented = false
    @State private var startFocusStep = StartFocusSheetStep.modePicker
    @State private var startFocusSheetHeight: CGFloat = 360
    @State private var isFishCatchSheetPresented = false
    @State private var isFocusResultOverlayDismissed = false
    @State private var isSnapshotDatePickerPresented = false
    @State private var snapshotPickerDate = Date()
    @State private var hasTrackedHomeView = false

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ScrollView {
                    GeometryReader { viewport in
                        VStack(spacing: PicoSpacing.compact) {
                            VillageHeroSection(
                                residents: [],
                                currentUserProfile: heroCurrentUserProfile,
                                participants: heroParticipants,
                                isLoading: heroIsLoading,
                                notice: heroNotice,
                                isFishingMode: focusStore.activeSession?.isLive == true,
                                mapStyle: heroMapStyle,
                                height: villageHeight(for: viewport.size.height)
                            )

                        }
                        .padding(.horizontal, PicoSpacing.standard)
                        .padding(.vertical, PicoSpacing.compact)
                    }
                    .containerRelativeFrame(.vertical)
                }
                .refreshable {
                    await refreshVillagePage()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let activeSession = focusStore.activeSession {
                    ActiveSessionTimerBottomBar(session: activeSession)
                } else {
                    HomeFocusBottomBar(
                        mode: bottomBarMode,
                        isLoadingBalance: berryStore.isLoadingBalance,
                        balanceNotice: berryStore.notice,
                        incomingInviteCount: focusStore.incomingInvites.count,
                        action: performBottomBarAction
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if focusStore.activeSession == nil {
                    HomeTopBar(
                        berryCount: berryStore.balance.berries,
                        completionStreak: berryStore.completionStreak,
                        showsMenuButton: showsMenuButton,
                        openNavigation: openNavigation,
                        chooseDateAction: presentSnapshotDatePicker
                    )
                }
            }
            .allowsHitTesting(!showsFocusResultOverlay)

            if showsFocusResultOverlay, let resultSession = focusStore.resultSession {
                FocusCompleteOverlay(
                    session: resultSession,
                    completionContext: focusStore.completionContext,
                    failureContext: focusStore.failureContext,
                    done: finishFocusResultOverlay
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(.snappy(duration: 0.22), value: focusStore.resultSession?.id)
        .picoScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isStartFocusSheetPresented) {
            StartFocusSheet(
                step: $startFocusStep,
                isPresented: $isStartFocusSheetPresented,
                measuredHeight: $startFocusSheetHeight,
                usesContentSizedLayout: usesContentSizedStartFocusSheet
            )
            .presentationDetents(startFocusSheetDetents)
            .presentationDragIndicator(.visible)
            .presentationBackground(PicoColors.appBackground)
            .presentationCornerRadius(PicoCreamCardStyle.sheetCornerRadius)
        }
        .fullScreenCover(isPresented: $isSnapshotDatePickerPresented) {
            DailySnapshotCalendarScreen(
                initialDate: snapshotPickerDate,
                maximumDate: snapshotPickerMaximumDate,
                fetchFocusActivityAction: fetchCalendarFocusActivity,
                fetchSnapshotAction: fetchCalendarSnapshot,
                fetchFocusDistributionAction: fetchCalendarFocusDistribution,
                fetchDailyFocusGoalAction: fetchCalendarDailyFocusGoal,
                updateDailyFocusGoalAction: updateCalendarDailyFocusGoal
            )
        }
        .fullScreenCover(isPresented: $isFishCatchSheetPresented, onDismiss: finishFishCatchFlow) {
            FishCatchRevealView(
                session: focusStore.resultSession,
                catches: fishStore.currentSessionCatches,
                catalog: fishStore.fishCatalog,
                isLoading: fishStore.isLoadingSessionCatches,
                notice: fishStore.notice,
                onRetry: retryCompletedSessionFishFetch,
                onDone: {
                    isFishCatchSheetPresented = false
                }
            )
        }
        .task {
            await sessionStore.loadProfileIfNeeded()
            await villageStore.loadResidents(for: sessionStore.session)
            await berryStore.loadBalance(for: sessionStore.session)
        }
        .onAppear {
            trackHomeViewIfNeeded()
        }
        .onChange(of: focusStore.resultSession) {
            guard focusStore.resultSession != nil else {
                fishStore.clearSessionCatches()
                isFocusResultOverlayDismissed = false
                return
            }
            isFocusResultOverlayDismissed = false
            isStartFocusSheetPresented = false
        }
        .onChange(of: focusStore.activeSession) {
            guard focusStore.activeSession != nil else { return }
            isStartFocusSheetPresented = false
        }
    }

    private var usesContentSizedStartFocusSheet: Bool {
        if focusStore.lobbySession?.mode == .solo {
            return true
        }
        guard focusStore.lobbySession == nil else { return false }
        return startFocusStep == .modePicker
            || startFocusStep == .soloConfig
            || startFocusStep == .multiplayerConfig
    }

    private var startFocusSheetDetents: Set<PresentationDetent> {
        guard usesContentSizedStartFocusSheet else {
            return [.medium, .large]
        }
        let height = max(220, ceil(startFocusSheetHeight))
        return [.height(height)]
    }

    private var heroCurrentUserProfile: UserProfile? {
        sessionStore.profile
    }

    private var heroParticipants: [IslandParticipant]? {
        if isLiveFocusActive {
            return activeIslandParticipants
        }

        return currentIslandParticipants
    }

    private var heroMapStyle: VillageMapStyle {
        islandStore.selectedIsland.mapStyle
    }

    private var heroIsLoading: Bool {
        villageStore.isLoadingResidents
    }

    private var heroNotice: String? {
        villageStore.notice
    }

    private var isLiveFocusActive: Bool {
        focusStore.activeSession?.isLive == true
    }

    private var snapshotPickerMaximumDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func visibleBondLevel(for resident: VillageResident) -> Int {
        villageStore.visibleBondLevel(
            for: resident,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }

    private func islandParticipant(for resident: VillageResident) -> IslandParticipant {
        IslandParticipant(
            profile: resident.profile,
            bondLevel: visibleBondLevel(for: resident)
        )
    }

    private var activeIslandParticipants: [IslandParticipant]? {
        guard let activeSession = focusStore.activeSession,
              activeSession.isLive else {
            return nil
        }

        let bondLevelByUserID = Dictionary(
            villageStore.residents.map { resident in
                (resident.profile.userID, visibleBondLevel(for: resident))
            },
            uniquingKeysWith: { current, _ in current }
        )

        guard activeSession.mode == .multiplayer else {
            guard let currentUserProfile = sessionStore.profile else { return [] }
            return [
                IslandParticipant(
                    profile: currentUserProfile,
                    bondLevel: bondLevelByUserID[currentUserProfile.userID] ?? 0
                )
            ]
        }

        guard let detail = focusStore.sessionDetail,
              detail.session.id == activeSession.id,
              detail.session.isLive else {
            return nil
        }

        return detail.members
            .filter { $0.status == .joined }
            .map { member in
                IslandParticipant(
                    profile: member.profile,
                    bondLevel: bondLevelByUserID[member.userID] ?? 0
                )
            }
    }

    private var currentIslandParticipants: [IslandParticipant]? {
        guard let currentUserProfile = sessionStore.profile else {
            return villageStore.residents.map(islandParticipant(for:))
        }

        return [IslandParticipant(profile: currentUserProfile, bondLevel: 0)] + villageStore.residents
            .filter { $0.profile.userID != currentUserProfile.userID }
            .map(islandParticipant(for:))
    }

    private var completedResultSession: FocusSession? {
        guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return nil }
        return resultSession
    }

    private var showsFocusResultOverlay: Bool {
        focusStore.resultSession != nil && !isFocusResultOverlayDismissed
    }

    private var bottomBarMode: StartFocusCTA.Mode {
        completedResultSession == nil ? .startFocus : .viewFish
    }

    private func presentStartFocusSheet() {
        guard focusStore.activeSession == nil else { return }
        guard !isStartFocusSheetPresented else { return }

        if let lobbySession = focusStore.lobbySession {
            startFocusStep = lobbySession.mode == .solo ? .soloConfig : .multiplayerLobby
        } else {
            startFocusStep = .modePicker
        }

        Analytics.track(AnalyticsEvent(id: .focusSetupViewed))
        isStartFocusSheetPresented = true
    }

    private func performBottomBarAction() {
        if completedResultSession == nil {
            presentStartFocusSheet()
        } else {
            viewCompletedSessionFish()
        }
    }

    private func refreshVillagePage() async {
        await sessionStore.reloadProfile()
        await refreshLiveVillageData(
            session: sessionStore.session,
            focusStore: focusStore,
            villageStore: villageStore
        )
        await friendStore.loadFriends(for: sessionStore.session)
        await berryStore.loadBalance(for: sessionStore.session)
    }

    private func presentSnapshotDatePicker() {
        guard !isLiveFocusActive else { return }

        snapshotPickerDate = snapshotPickerMaximumDate
        isSnapshotDatePickerPresented = true
    }

    private func fetchCalendarSnapshot(day: DailySnapshotDay) async throws -> DailyVillageSnapshot? {
        guard let session = sessionStore.session else { return nil }
        return try await dailySnapshotService.fetchSnapshot(day: day, for: session)
    }

    private func fetchCalendarFocusActivity(
        startDay: DailySnapshotDay,
        endDay: DailySnapshotDay
    ) async throws -> [DailySnapshotFocusActivity] {
        guard let session = sessionStore.session else { return [] }
        return try await dailySnapshotService.listFocusActivity(
            startDay: startDay,
            endDay: endDay,
            for: session
        )
    }

    private func fetchCalendarDailyFocusGoal() async throws -> Int? {
        guard let session = sessionStore.session else { return nil }
        return try await dailySnapshotService.fetchDailyFocusGoal(for: session)
    }

    private func fetchCalendarFocusDistribution(day: DailySnapshotDay) async throws -> DailyFocusDistribution {
        guard let session = sessionStore.session else { return .empty(day: day) }
        return try await dailySnapshotService.fetchFocusDistribution(day: day, for: session)
    }

    private func updateCalendarDailyFocusGoal(minutes: Int?) async throws -> Int? {
        guard let session = sessionStore.session else { return nil }
        return try await dailySnapshotService.updateDailyFocusGoal(minutes: minutes, for: session)
    }

    private func villageHeight(for viewportHeight: CGFloat) -> CGFloat {
        max(280, viewportHeight - 54)
    }

    private func viewCompletedSessionFish() {
        guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return }
        isFishCatchSheetPresented = true
        Task {
            if fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
                await fishStore.loadFishCatalog(
                    for: sessionStore.session,
                    islandID: islandStore.selectedIslandID
                )
            }
            await fishStore.loadSessionCatches(
                sessionID: resultSession.id,
                for: sessionStore.session,
                retryIfEmpty: true
            )
        }
    }

    private func retryCompletedSessionFishFetch() {
        guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return }
        Task {
            if fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
                await fishStore.loadFishCatalog(
                    for: sessionStore.session,
                    islandID: islandStore.selectedIslandID
                )
            }
            await fishStore.loadSessionCatches(
                sessionID: resultSession.id,
                for: sessionStore.session,
                retryIfEmpty: true
            )
        }
    }

    private func finishFishCatchFlow() {
        fishStore.clearSessionCatches()
        if focusStore.resultSession?.status == .completed {
            focusStore.resetResult()
        }
    }

    private func finishFocusResultOverlay() {
        if focusStore.resultSession?.status == .completed {
            isFocusResultOverlayDismissed = true
        } else {
            focusStore.resetResult()
        }
    }

    private func trackHomeViewIfNeeded() {
        guard !hasTrackedHomeView else { return }
        hasTrackedHomeView = true
        Analytics.track(AnalyticsEvent(id: .homeViewed))
    }
}

private struct FishCatchRevealView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage = 0
    @State private var hasTrackedReveal = false

    let session: FocusSession?
    let catches: [FishCatch]
    let catalog: [FishCatalogItem]
    let isLoading: Bool
    let notice: String?
    let onRetry: () -> Void
    let onDone: () -> Void

    private var rows: [CaughtFishRow] {
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return catches.map { fishCatch in
            CaughtFishRow(
                fishCatch: fishCatch,
                catalogItem: catalogByID[fishCatch.seaCritterID]
            )
        }
    }

    var body: some View {
        ZStack {
            revealBackground

            if isLoading {
                loadingState
            } else if rows.isEmpty {
                emptyState
            } else {
                loadedReveal
            }
        }
        .picoScreenBackground()
        .onAppear {
            trackRevealIfReady()
        }
        .onChange(of: isLoading) {
            trackRevealIfReady()
        }
        .onChange(of: rows.count) {
            clampSelectedPage(for: rows.count)
            trackRevealIfReady()
        }
    }

    private var revealBackground: some View {
        ZStack {
            PicoColors.appBackground
            activeRarityStyle.rowBackgroundColor.opacity(rows.isEmpty ? 0 : 0.62)
        }
        .ignoresSafeArea()
    }

    private var activeRarityStyle: PicoFishRarityStyle {
        guard !rows.isEmpty else { return FishRarity.common.picoStyle }
        return rows[min(selectedPage, rows.count - 1)].rarityStyle
    }

    private var loadingState: some View {
        VStack(spacing: PicoSpacing.standard) {
            ProgressView()
                .tint(PicoColors.primary)
                .scaleEffect(1.12)

            Text("Getting your catch ready")
                .font(PicoTypography.primaryLabelSemibold)
                .foregroundStyle(PicoColors.textSecondary)
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
    }

    private var emptyState: some View {
        VStack(spacing: PicoSpacing.standard) {
            Spacer(minLength: 0)

            Text(notice ?? "No fish found for this session yet.")
                .font(PicoTypography.body)
                .foregroundStyle(PicoColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(PicoSecondaryButtonStyle())

            Spacer(minLength: 0)

            Button("Done") {
                onDone()
            }
            .buttonStyle(PicoPrimaryButtonStyle())
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.vertical, PicoSpacing.section)
    }

    private var loadedReveal: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)

                    if selectedPage < rows.count {
                        Button("Skip") {
                            withAnimation(.snappy(duration: 0.24)) {
                                selectedPage = rows.count
                            }
                        }
                        .font(PicoTypography.smallAction)
                        .foregroundStyle(PicoColors.textSecondary)
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 32)
                .padding(.top, PicoSpacing.standard)
                .padding(.horizontal, PicoSpacing.cardPadding)

                TabView(selection: $selectedPage) {
                    ForEach(rows.indices, id: \.self) { index in
                        FishCatchRevealPage(
                            row: rows[index],
                            reduceMotion: reduceMotion
                        )
                        .tag(index)
                    }

                    FishCatchSummaryPage(rows: rows)
                        .tag(rows.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if selectedPage >= rows.count {
                    Button("Done") {
                        onDone()
                    }
                    .buttonStyle(PicoPrimaryButtonStyle())
                    .padding(.horizontal, PicoSpacing.cardPadding)
                    .padding(.bottom, PicoSpacing.standard)
                } else {
                    Color.clear
                        .frame(height: 52)
                        .padding(.bottom, PicoSpacing.standard)
                }
            }

            if selectedPage < rows.count {
                Button {
                    advanceRevealPage()
                } label: {
                    PicoIcon(.chevronRightRegular, size: 21)
                        .foregroundStyle(PicoColors.textSecondary)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .padding(.trailing, PicoSpacing.standard)
                .accessibilityLabel(Text(selectedPage == rows.count - 1 ? "View catch summary" : "Next catch"))
            }
        }
    }

    private func clampSelectedPage(for rowCount: Int) {
        guard rowCount > 0 else {
            selectedPage = 0
            return
        }

        selectedPage = min(selectedPage, rowCount)
    }

    private func advanceRevealPage() {
        withAnimation(.snappy(duration: 0.24)) {
            selectedPage = min(selectedPage + 1, rows.count)
        }
    }

    private func trackRevealIfReady() {
        guard !hasTrackedReveal, !isLoading else { return }
        hasTrackedReveal = true
        Analytics.track(AnalyticsEvent(
            id: .catchRevealViewed,
            parameters: [
                .catchCount: .int(catches.count),
                .bestRarity: .string(bestRarityAnalyticsValue(in: catches)),
                .sessionType: .string(session?.mode.rawValue ?? "unknown")
            ]
        ))
    }
}

private struct FishCatchRevealPage: View {
    let row: CaughtFishRow
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let heroSize = min(min(proxy.size.width * 0.66, proxy.size.height * 0.34), 260)

            ZStack {
                FocusCompleteConfettiView(reduceMotion: reduceMotion)
                    .frame(width: min(proxy.size.width * 0.86, 360), height: min(proxy.size.height * 0.42, 280))
                    .offset(y: -heroSize * 0.04)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Text("You caught")
                        .font(PicoTypography.primaryLabelSemibold)
                        .foregroundStyle(PicoColors.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                        .frame(height: PicoSpacing.largeSection + PicoSpacing.iconTextGap)

                    FishCatchHeroIcon(
                        row: row,
                        size: heroSize
                    )

                    Spacer()
                        .frame(height: 0)

                    VStack(spacing: PicoSpacing.iconTextGap) {
                        Text(row.label)
                            .font(PicoTypography.screenTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.58)
                            .allowsTightening(true)

                        FishCatchRarityBadge(row: row)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PicoSpacing.cardPadding)
                .padding(.bottom, PicoSpacing.standard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FishCatchHeroIcon: View {
    let row: CaughtFishRow
    let size: CGFloat

    var body: some View {
        FishCatchIcon(
            row: row,
            size: size,
            imagePadding: 0,
            showsChrome: false
        )
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.label))
    }
}

private struct FishCatchRarityBadge: View {
    let row: CaughtFishRow

    var body: some View {
        Text(row.rarityLabel)
            .font(PicoTypography.largePill)
            .foregroundStyle(row.rarityStyle.pillTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .padding(.vertical, 6)
            .background(row.rarityStyle.pillBackgroundColor)
            .clipShape(Capsule(style: .continuous))
    }
}

private struct FishCatchSummaryPage: View {
    let rows: [CaughtFishRow]

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            Spacer(minLength: 0)

            Text("Catch summary")
                .font(PicoTypography.sectionTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: PicoSpacing.iconTextGap) {
                ForEach(rows) { row in
                    FishCatchSummaryRow(row: row)
                }
            }
            .padding(.top, PicoSpacing.compact)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.bottom, PicoSpacing.standard)
    }
}

private struct FishCatchSummaryRow: View {
    let row: CaughtFishRow

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            FishCatchIcon(
                row: row,
                size: 58,
                imagePadding: 0,
                showsChrome: false
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(row.label)
                    .font(PicoTypography.compactTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                FishCatchRarityBadge(row: row)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PicoSpacing.standard)
        .padding(.vertical, PicoSpacing.iconTextGap)
        .background(row.rarityStyle.rowBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(row.rarityStyle.rowBorderColor, lineWidth: 1)
        )
    }
}

private struct CaughtFishRow: Identifiable {
    let fishCatch: FishCatch
    let catalogItem: FishCatalogItem?

    var id: UUID {
        fishCatch.id
    }

    var fishID: FishID {
        fishCatch.seaCritterID
    }

    var rarity: FishRarity {
        fishCatch.rarity
    }

    var label: String {
        catalogItem?.displayName ?? fishID.displayName
    }

    var rarityLabel: String {
        rarity.label
    }

    var rarityStyle: PicoFishRarityStyle {
        rarity.picoStyle
    }

    var imageResourceName: String {
        catalogItem?.assetName ?? fishID.assetName
    }

    var imageResourceCandidates: [String] {
        fishImageResourceCandidates(named: imageResourceName)
    }
}

private struct FishCatchIcon: View {
    let row: CaughtFishRow
    var size: CGFloat = 34
    var imagePadding: CGFloat = 5
    var showsChrome = true

    var body: some View {
        iconContent
            .frame(width: size, height: size)
            .background {
                if showsChrome {
                    RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                        .fill(row.rarityStyle.rowBackgroundColor)
                }
            }
            .overlay {
                if showsChrome {
                    RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                        .stroke(row.rarityStyle.rowBorderColor, lineWidth: 1)
                }
            }
            .shadow(color: showsChrome ? row.rarityStyle.rowBorderColor.opacity(0.5) : .clear, radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let image = fishImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(imagePadding)
        } else {
            Image(systemName: "fish")
                .font(PicoTypography.symbol(size: size * 0.62, weight: .semibold))
                .foregroundStyle(row.rarityStyle.iconFallbackColor)
        }
    }

    private var fishImage: UIImage? {
        row.imageResourceCandidates.lazy.compactMap { UIImage(named: $0) }.first
    }
}

@MainActor
private func refreshLiveVillageData(
    session: AuthSession?,
    focusStore: FocusStore,
    villageStore: VillageStore
) async {
    await focusStore.refresh(for: session)
    await villageStore.loadResidents(for: session, force: true)
}

private struct HomeTopBar: View {
    let berryCount: Int
    let completionStreak: Int
    let showsMenuButton: Bool
    let openNavigation: () -> Void
    let chooseDateAction: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if showsMenuButton {
                    PicoNavigationMenuButton(action: openNavigation)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
            }

            Spacer(minLength: 0)

            HomeTopBarCalendarStats(
                berryCount: berryCount,
                completionStreak: completionStreak,
                chooseDateAction: chooseDateAction
            )
        }
        .padding(.horizontal, PicoSpacing.standard)
        .frame(height: 68, alignment: .top)
        .background(PicoColors.appBackground)
    }
}

private struct HomeTopBarCalendarStats: View {
    let berryCount: Int
    let completionStreak: Int
    let chooseDateAction: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: PicoSpacing.compact) {
                berryCountRow
                    .frame(height: 44)
                    .accessibilityLabel(Text(formattedBerryCount(berryCount)))

                streakCount
                    .frame(height: 44)

                Button(action: chooseDateAction) {
                    Image(systemName: "calendar")
                        .font(PicoTypography.symbol(size: 20, weight: .semibold))
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open calendar picker"))
            }
        }
        .frame(minWidth: 156, alignment: .topTrailing)
    }

    private var streakCount: some View {
        HStack(spacing: PicoSpacing.tiny) {
            PicoIcon(.fireSolid, size: 20)
                .foregroundStyle(PicoColors.streakAccent)

            Text("\(completionStreak)")
                .font(PicoTypography.countValue)
                .foregroundStyle(PicoColors.textPrimary)
                .monospacedDigit()
        }
        .accessibilityLabel(Text("\(completionStreak) day streak"))
    }

    private var berryCountRow: some View {
        HStack(spacing: PicoSpacing.tiny) {
            BerryBalanceIcon(size: 22)

            Text("\(berryCount)")
                .font(PicoTypography.countValue)
                .foregroundStyle(PicoColors.textPrimary)
                .monospacedDigit()
        }
    }
}

private struct BerryBalanceIcon: View {
    let size: CGFloat

    var body: some View {
        if let image = UIImage(named: "Berry_Icon") ?? UIImage(named: "Berries_Icon") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            PicoIcon(.sparklesSolid, size: size)
                .foregroundStyle(PicoColors.primary)
        }
    }
}

private struct PicoScreenTopBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack(alignment: .top) {
            Text(title)
                .font(PicoTypography.topBarTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .frame(height: 44)

            HStack(alignment: .top) {
                leading()

                Spacer(minLength: 0)

                trailing()
            }
        }
        .padding(.horizontal, PicoSpacing.standard)
        .frame(height: 48, alignment: .top)
        .background(PicoColors.appBackground)
    }
}

private struct PicoNavigationMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PicoIcon(.bars3Solid, size: 22)
                .foregroundStyle(PicoColors.textPrimary)
                .frame(width: 44, height: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open navigation"))
    }
}

private struct BondsPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var villageStore: VillageStore

    var body: some View {
        ScrollView {
            BondsContent()
                .padding(PicoSpacing.standard)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
        }
        .refreshable {
            await refreshLiveVillageData(
                session: sessionStore.session,
                focusStore: focusStore,
                villageStore: villageStore
            )
        }
    }
}

struct BondsContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    @State private var claimedReward: BondRewardClaimCelebration?

    private var bonds: [VillageResident] {
        villageStore.residents
            .filter { $0.completedPairSessions > 0 }
            .sorted {
                if $0.bondLevel != $1.bondLevel {
                    return $0.bondLevel > $1.bondLevel
                }

                if $0.completedPairSessions != $1.completedPairSessions {
                    return $0.completedPairSessions > $1.completedPairSessions
                }

                return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            bondsContent

            if let notice = villageStore.notice {
                Text(notice)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PicoSpacing.standard)
                    .background(
                        RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                            .fill(PicoCreamCardStyle.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                            .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
                    )
            }

            if let notice = picoPlusStore.notice {
                ProfileNoticeCard(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $claimedReward) { celebration in
            BondRewardCelebrationSheet(celebration: celebration) {
                claimedReward = nil
            }
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.visible)
            .presentationBackground(PicoColors.appBackground)
            .presentationCornerRadius(PicoCreamCardStyle.sheetCornerRadius)
        }
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    @ViewBuilder
    private var bondsContent: some View {
        if villageStore.isLoadingResidents {
            HStack(spacing: PicoSpacing.standard) {
                Text("Loading bonds")
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                ProgressView()
                    .tint(PicoColors.primary)
            }
            .padding(PicoSpacing.standard)
            .picoCreamCard(showsShadow: false)
        } else if bonds.isEmpty {
            VStack(spacing: PicoSpacing.compact) {
                if let greenScarfImage {
                    Image(uiImage: greenScarfImage)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }

                Text("No bonds yet")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Complete focus sessions with friends to grow bonds.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(PicoSpacing.cardPadding)
            .picoCreamCard(showsShadow: false)
        } else {
            BondsGroupedList(
                residents: bonds,
                ownerID: currentUserID,
                onClaim: claimReward
            )
        }
    }

    private var greenScarfImage: UIImage? {
        [
            "Icons/Scarf_Green",
            "Icons/Scarf_Green.png",
            "Scarf_Green",
            "Scarf_Green.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }

    private func claimReward(for resident: VillageResident) {
        guard let currentUserID else { return }

        let claimedLevel = bondRewardClaimStore.claimedLevel(
            ownerID: currentUserID,
            residentID: resident.id
        )

        guard let reward = BondScarfReward.nextClaimable(
            earnedLevel: resident.bondLevel,
            claimedLevel: claimedLevel
        ) else {
            return
        }

        if !picoPlusStore.capabilities.canClaimBondReward(level: reward.level) {
            Task { @MainActor in
                await picoPlusStore.presentPaywall(
                    source: reward.picoPlusPaywallSource(residentID: resident.id),
                    authSession: sessionStore.session
                )

                guard picoPlusStore.capabilities.canClaimBondReward(level: reward.level) else { return }
                claimHighestAvailableReward(for: resident, ownerID: currentUserID)
            }
            return
        }

        if picoPlusStore.capabilities.canClaimAllBondRewards {
            claimHighestAvailableReward(for: resident, ownerID: currentUserID)
            return
        }

        claim(reward: reward, for: resident, ownerID: currentUserID)
    }

    private func claimHighestAvailableReward(for resident: VillageResident, ownerID: UUID) {
        let claimedLevel = bondRewardClaimStore.claimedLevel(
            ownerID: ownerID,
            residentID: resident.id
        )

        guard let reward = BondScarfReward.highestClaimable(
            earnedLevel: resident.bondLevel,
            claimedLevel: claimedLevel
        ) else {
            return
        }

        guard picoPlusStore.capabilities.canClaimBondReward(level: reward.level) else {
            return
        }

        claim(reward: reward, for: resident, ownerID: ownerID)
    }

    private func claim(reward: BondScarfReward, for resident: VillageResident, ownerID: UUID) {
        bondRewardClaimStore.markClaimed(
            level: reward.level,
            ownerID: ownerID,
            residentID: resident.id
        )

        claimedReward = BondRewardClaimCelebration(
            reward: reward,
            currentProfile: sessionStore.profile,
            resident: resident
        )
    }
}

private struct BondsGroupedList: View {
    let residents: [VillageResident]
    let ownerID: UUID?
    let onClaim: (VillageResident) -> Void

    private var groups: [BondLevelGroup] {
        Dictionary(grouping: residents, by: \.bondLevel)
            .map { level, residents in
                BondLevelGroup(
                    level: level,
                    residents: residents.sorted {
                        if $0.completedPairSessions != $1.completedPairSessions {
                            return $0.completedPairSessions > $1.completedPairSessions
                        }

                        return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.level > $1.level }
    }

    var body: some View {
        VStack(spacing: PicoSpacing.largeSection) {
            ForEach(groups) { group in
                BondLevelGroupView(
                    group: group,
                    ownerID: ownerID,
                    onClaim: onClaim
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BondLevelGroup: Identifiable {
    let level: Int
    let residents: [VillageResident]

    var id: Int { level }

    var scarf: AvatarScarf? {
        AvatarScarf(bondLevel: level)
    }
}

private struct BondLevelGroupView: View {
    let group: BondLevelGroup
    let ownerID: UUID?
    let onClaim: (VillageResident) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.iconTextGap) {
            heading
                .padding(.horizontal, PicoSpacing.iconTextGap)

            VStack(spacing: 0) {
                ForEach(Array(group.residents.enumerated()), id: \.element.id) { index, resident in
                    BondRowView(
                        resident: resident,
                        ownerID: ownerID,
                        onClaim: onClaim
                    )

                    if index < group.residents.count - 1 {
                        PicoCardDivider()
                            .padding(.leading, 72)
                    }
                }
            }
            .picoCreamCard(showsShadow: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        HStack(spacing: PicoSpacing.compact) {
            if let scarf = group.scarf {
                BondScarfIcon(scarf: scarf)
                    .frame(width: 24, height: 20)
            }

            Text("Level \(group.level)")
                .font(PicoTypography.primaryLabelSemibold)
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityHeading))
    }

    private var accessibilityHeading: String {
        guard let scarf = group.scarf else {
            return "Level \(group.level)"
        }

        return "\(scarf.displayName) scarf, Level \(group.level)"
    }
}

private struct BondRowView: View {
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let resident: VillageResident
    let ownerID: UUID?
    let onClaim: (VillageResident) -> Void

    private var xp: Int {
        resident.completedPairSessions
    }

    private var claimedLevel: Int {
        bondRewardClaimStore.claimedLevel(ownerID: ownerID, residentID: resident.id)
    }

    private var pendingReward: BondScarfReward? {
        guard ownerID != nil else { return nil }

        return BondScarfReward.nextClaimable(
            earnedLevel: resident.bondLevel,
            claimedLevel: claimedLevel
        )
    }

    private var visibleBondLevel: Int {
        picoPlusStore.capabilities.visibleBondRewardLevel(
            earnedLevel: resident.bondLevel,
            claimedLevel: claimedLevel
        )
    }

    private var pendingRewardRequiresPlus: Bool {
        guard let pendingReward else { return false }
        return picoPlusStore.capabilities.bondRewardRequiresPlus(level: pendingReward.level)
    }

    private var scarfProgress: BondScarfProgress {
        BondScarfProgress(
            xp: xp,
            claimableReward: pendingReward,
            claimableRewardRequiresPlus: pendingRewardRequiresPlus
        )
    }

    private var hasPendingReward: Bool {
        pendingReward != nil
    }

    private var rowBackground: Color {
        hasPendingReward ? PicoColors.highlightBackground.opacity(0.18) : .clear
    }

    var body: some View {
        Group {
            if hasPendingReward && !pendingRewardRequiresPlus {
                Button {
                    onClaim(resident)
                } label: {
                    rowSurface
                }
                .buttonStyle(.plain)
            } else {
                rowSurface
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(resident.profile.displayName), bond level \(resident.bondLevel), \(xp) sessions, \(scarfProgress.accessibilitySummary)")
        )
    }

    private var rowSurface: some View {
        rowContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PicoSpacing.cardPadding)
            .padding(.vertical, PicoSpacing.standard)
            .background(rowBackground)
            .contentShape(Rectangle())
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            HStack(spacing: PicoSpacing.standard) {
                AvatarBadgeView(
                    config: resident.profile.avatarConfig,
                    size: 56,
                    scarf: AvatarScarf(bondLevel: visibleBondLevel)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(resident.profile.displayName)
                        .font(PicoTypography.primaryLabelSemibold)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    HStack(spacing: PicoSpacing.tiny) {
                        Text("@\(resident.profile.username)")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: PicoSpacing.tiny)

                        if let progressLabel = scarfProgress.caption {
                            HStack(spacing: 5) {
                                Text(progressLabel)
                                    .font(PicoTypography.tinyCaption)
                                    .foregroundStyle(PicoColors.textSecondary)
                                    .lineLimit(1)

                                if let captionScarf = scarfProgress.captionScarf {
                                    BondScarfIcon(scarf: captionScarf)
                                        .frame(width: 16, height: 14)
                                }
                            }
                            .layoutPriority(1)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if let pendingReward, pendingRewardRequiresPlus {
                    PicoPlusCTAButton(
                        size: .pill,
                        source: pendingReward.picoPlusPaywallSource(residentID: resident.id),
                        afterPresentation: {
                            if picoPlusStore.capabilities.canClaimBondReward(level: pendingReward.level) {
                                onClaim(resident)
                            }
                        }
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                } else {
                    Spacer(minLength: 0)
                }
            }

            BondScarfProgressBar(progress: scarfProgress)
                .padding(.leading, 56 + PicoSpacing.standard)
                .accessibilityHidden(true)
        }
    }
}

private struct BondScarfIcon: View {
    let scarf: AvatarScarf?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else if scarf == nil {
                Color.clear
            } else {
                Image(systemName: "gift.fill")
                    .font(PicoTypography.symbol(size: 22, weight: .semibold))
                    .foregroundStyle(PicoColors.primary)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        guard let scarf else { return nil }

        return scarf.iconResourceCandidates
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct BondScarfProgressBar: View {
    let progress: BondScarfProgress

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<progress.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index < progress.filledSegmentCount ? progress.tint : PicoColors.softSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(PicoColors.border.opacity(index < progress.filledSegmentCount ? 0 : 1), lineWidth: 1)
                    )
                    .frame(height: 6)
            }
        }
    }
}

private struct BondScarfProgress {
    let xp: Int
    let claimableReward: BondScarfReward?
    let claimableRewardRequiresPlus: Bool

    private var targetMilestone: BondScarfMilestone? {
        if let claimableReward {
            return BondScarfMilestone.all.first { $0.level == claimableReward.level }
        }

        return BondScarfMilestone.all.first { xp < $0.requiredXP }
    }

    private var previousRequiredXP: Int {
        guard let targetMilestone else {
            return BondScarfMilestone.all.last?.requiredXP ?? 0
        }

        return BondScarfMilestone.all.last { $0.requiredXP < targetMilestone.requiredXP }?.requiredXP ?? 0
    }

    private var requiredDelta: Int {
        guard let targetMilestone else {
            return 1
        }

        return max(targetMilestone.requiredXP - previousRequiredXP, 1)
    }

    private var currentDelta: Int {
        if claimableReward != nil {
            return requiredDelta
        }

        return min(max(xp - previousRequiredXP, 0), requiredDelta)
    }

    var segmentCount: Int {
        requiredDelta
    }

    var filledSegmentCount: Int {
        guard targetMilestone != nil else {
            return segmentCount
        }

        return currentDelta
    }

    var tint: Color {
        if claimableReward != nil {
            return PicoColors.highlight
        }

        return PicoColors.primary
    }

    var caption: String? {
        if claimableRewardRequiresPlus {
            return nil
        }

        if claimableReward != nil {
            return "Tap to collect reward"
        }

        guard let targetMilestone else {
            return "All rewards unlocked"
        }

        let remainingSessions = max(targetMilestone.requiredXP - xp, 0)
        return remainingSessions == 1
            ? "1 session to"
            : "\(remainingSessions) sessions to"
    }

    var captionScarf: AvatarScarf? {
        guard claimableReward == nil, let targetMilestone else {
            return nil
        }

        return targetMilestone.scarf
    }

    var accessibilitySummary: String {
        if let claimableReward {
            if claimableRewardRequiresPlus {
                return "level \(claimableReward.level) reward requires Pico Plus"
            }

            return "level \(claimableReward.level) reward ready to claim"
        }

        guard let targetMilestone else {
            return "top scarf unlocked"
        }

        return "\(xp) of \(targetMilestone.requiredXP) sessions toward \(targetMilestone.name) scarf"
    }
}

private struct BondScarfMilestone {
    let level: Int
    let name: String
    let requiredXP: Int

    var scarf: AvatarScarf? {
        AvatarScarf(bondLevel: level)
    }

    static let all: [BondScarfMilestone] = [
        BondScarfMilestone(level: 2, name: "green", requiredXP: 3),
        BondScarfMilestone(level: 3, name: "blue", requiredXP: 6),
        BondScarfMilestone(level: 4, name: "orange", requiredXP: 9),
        BondScarfMilestone(level: 5, name: "purple", requiredXP: 12)
    ]
}

private struct BondScarfReward: Equatable {
    let level: Int
    let name: String

    var scarf: AvatarScarf? {
        AvatarScarf(bondLevel: level)
    }

    var displayName: String {
        name.capitalized
    }

    var requiresPicoPlus: Bool {
        PicoPlusCapabilities.free.bondRewardRequiresPlus(level: level)
    }

    func picoPlusPaywallSource(residentID: UUID) -> PicoPlusPaywallSource {
        .bondReward(
            residentID: residentID.uuidString,
            bondLevel: level,
            placement: .bondReward
        )
    }

    static func nextClaimable(earnedLevel: Int, claimedLevel: Int) -> BondScarfReward? {
        BondScarfMilestone.all
            .first { $0.level <= earnedLevel && $0.level > claimedLevel }
            .map { BondScarfReward(level: $0.level, name: $0.name) }
    }

    static func highestClaimable(earnedLevel: Int, claimedLevel: Int) -> BondScarfReward? {
        BondScarfMilestone.all
            .last { $0.level <= earnedLevel && $0.level > claimedLevel }
            .map { BondScarfReward(level: $0.level, name: $0.name) }
    }
}

private extension AvatarScarf {
    var displayName: String {
        switch self {
        case .green:
            "Green"
        case .blue:
            "Blue"
        case .orange:
            "Orange"
        case .purple:
            "Purple"
        }
    }

    var iconResourceCandidates: [String] {
        let iconName = switch self {
        case .green:
            "Scarf_Green"
        case .blue:
            "Scarf_Sky"
        case .orange:
            "Scarf_Orange"
        case .purple:
            "Scarf_Purple"
        }

        return [
            "Icons/\(iconName)",
            "Icons/\(iconName).png",
            iconName,
            "\(iconName).png"
        ]
    }
}

private struct BondRewardClaimCelebration: Identifiable {
    let id = UUID()
    let reward: BondScarfReward
    let currentProfile: UserProfile?
    let resident: VillageResident
}

private struct BondRewardCelebrationSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let celebration: BondRewardClaimCelebration
    let onDone: () -> Void

    private var currentAvatarConfig: AvatarConfig {
        celebration.currentProfile?.avatarConfig ?? AvatarCatalog.defaultConfig
    }

    private var currentDisplayName: String {
        celebration.currentProfile?.displayName ?? "You"
    }

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            VStack(spacing: PicoSpacing.compact) {
                Text("Bond reached level \(celebration.reward.level)")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(celebration.reward.displayName) scarf unlocked!")
                    .font(PicoTypography.bodySemibold)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                FocusCompleteConfettiView(reduceMotion: reduceMotion)
                    .frame(width: 280, height: 128)
                    .allowsHitTesting(false)

                HStack(spacing: PicoSpacing.standard) {
                    BondRewardCelebrationAvatar(
                        displayName: currentDisplayName,
                        avatarConfig: currentAvatarConfig,
                        scarf: celebration.reward.scarf
                    )

                    BondRewardCelebrationAvatar(
                        displayName: celebration.resident.profile.displayName,
                        avatarConfig: celebration.resident.profile.avatarConfig,
                        scarf: celebration.reward.scarf
                    )
                }
            }
            .frame(height: 156)
            .clipped()

            Button("Done") {
                onDone()
            }
            .buttonStyle(PicoPrimaryButtonStyle())
            .padding(.top, PicoSpacing.compact)
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.top, PicoSpacing.section)
        .padding(.bottom, PicoSpacing.standard)
    }
}

private struct BondRewardCelebrationAvatar: View {
    let displayName: String
    let avatarConfig: AvatarConfig
    let scarf: AvatarScarf?

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            UserAvatar(
                config: avatarConfig,
                maxSpriteSide: 118,
                usesHappyIdle: true,
                scarf: scarf
            )
            .frame(width: 130, height: 116)

            Text(displayName)
                .font(PicoTypography.captionSemibold)
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 124)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayName))
    }
}

private enum StartFocusSheetStep {
    case modePicker
    case soloConfig
    case multiplayerConfig
    case multiplayerLobby
    case multiplayerInviteMore
    case invites
}

private struct VillageHeroSection: View {
    let residents: [VillageResident]
    let currentUserProfile: UserProfile?
    let participants: [IslandParticipant]?
    let isLoading: Bool
    let notice: String?
    let isFishingMode: Bool
    let mapStyle: VillageMapStyle
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            VillageView(
                residents: residents,
                currentUserProfile: currentUserProfile,
                participants: participants,
                isFishingMode: isFishingMode,
                mapStyle: mapStyle
            )
                .frame(maxWidth: .infinity)
                .frame(height: height)

            villageStatusOverlay
                .padding(PicoSpacing.standard)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.large, style: .continuous))
    }

    @ViewBuilder
    private var villageStatusOverlay: some View {
        if isLoading || notice != nil {
            HStack(spacing: PicoSpacing.compact) {
                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)

                    Text("Loading village")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                } else if let notice {
                    PicoIcon(.infoRegular, size: 16)
                        .foregroundStyle(PicoColors.warning)

                    Text(notice)
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .padding(.vertical, PicoSpacing.compact)
            .background(
                Capsule(style: .continuous)
                    .fill(PicoColors.surface.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PicoColors.border, lineWidth: 1)
            )
        }
    }
}

private enum DailySnapshotHeroMode: String, CaseIterable, Identifiable {
    case fish
    case bonds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bonds:
            "Bonds"
        case .fish:
            "Catches"
        }
    }

    var iconName: String {
        switch self {
        case .bonds:
            "Scarf_Green"
        case .fish:
            "FishingPole_New"
        }
    }
}

private enum DailySnapshotScreenTab: String, CaseIterable, Identifiable {
    case calendar
    case stats

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendar:
            "Calendar"
        case .stats:
            "Stats"
        }
    }
}

private struct DailySnapshotCalendarScreen: View {
    let initialDate: Date
    let maximumDate: Date
    let fetchFocusActivityAction: (DailySnapshotDay, DailySnapshotDay) async throws -> [DailySnapshotFocusActivity]
    let fetchSnapshotAction: (DailySnapshotDay) async throws -> DailyVillageSnapshot?
    let fetchFocusDistributionAction: (DailySnapshotDay) async throws -> DailyFocusDistribution
    let fetchDailyFocusGoalAction: () async throws -> Int?
    let updateDailyFocusGoalAction: (Int?) async throws -> Int?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    @State private var selectedScreenTab: DailySnapshotScreenTab = .calendar
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var heroMode: DailySnapshotHeroMode = .fish
    @State private var selectedDate = Date()
    @State private var selectedStatsDate = Date()
    @State private var snapshotByDay: [DailySnapshotDay: DailyVillageSnapshot] = [:]
    @State private var focusActivityByDay: [DailySnapshotDay: Bool] = [:]
    @State private var focusDistributionByDay: [DailySnapshotDay: DailyFocusDistribution] = [:]
    @State private var loadedFocusActivityMonths: Set<DailySnapshotDay> = []
    @State private var loadingFocusActivityMonths: Set<DailySnapshotDay> = []
    @State private var loadingFocusDistributionDays: Set<DailySnapshotDay> = []
    @State private var loadState: DailySnapshotLoadState = .idle
    @State private var statsLoadState: DailySnapshotLoadState = .idle
    @State private var dailyFocusGoalMinutes: Int?
    @State private var isFocusGoalSheetPresented = false
    @State private var isLoadingFocusGoal = false
    @State private var isSavingFocusGoal = false
    @State private var focusGoalNotice: String?
    @State private var notice: String?
    @State private var statsNotice: String?

    private var calendar: Calendar {
        .current
    }

    private var selectedSnapshotDay: DailySnapshotDay {
        DailySnapshotDay(date: selectedDate, calendar: calendar)
    }

    private var selectedStatsDay: DailySnapshotDay {
        DailySnapshotDay(date: selectedStatsDate, calendar: calendar)
    }

    private var snapshotsByDay: [DailySnapshotDay: DailyVillageSnapshot] {
        snapshotByDay
    }

    private var selectedSnapshot: DailyVillageSnapshot? {
        snapshotByDay[selectedSnapshotDay]
    }

    private var selectedFocusDistribution: DailyFocusDistribution {
        focusDistributionByDay[selectedStatsDay] ?? .empty(day: selectedStatsDay)
    }

    private var displayedMonthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var canGoToNextMonth: Bool {
        monthStart(for: displayedMonth) < monthStart(for: maximumDate)
    }

    private var canGoToNextStatsDay: Bool {
        calendar.startOfDay(for: selectedStatsDate) < maximumDate
    }

    private var monthDays: [DailySnapshotCalendarDay] {
        makeMonthDays()
    }

    private var selectedDayRequiresPlus: Bool {
        !picoPlusStore.capabilities.canAccessDailySnapshot(isPastDay: isPastDay(selectedDate))
    }

    private var isStatsLocked: Bool {
        !picoPlusStore.capabilities.isPlusActive
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: PicoSpacing.section) {
                    header

                    Group {
                        switch selectedScreenTab {
                        case .calendar:
                            calendarTab
                        case .stats:
                            statsTab
                        }
                    }
                }
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.top, 0)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.section))
            }
            .scrollIndicators(.hidden)
        }
        .background(PicoCalendarStyle.background.ignoresSafeArea())
        .onAppear {
            selectedDate = initialDate
            selectedStatsDate = maximumDate
            let selectedMonth = monthStart(for: initialDate)
            displayedMonth = selectedMonth
            loadDisplayedMonthActivityIfNeeded(for: selectedMonth)
            loadSelectedSnapshotIfNeeded(for: initialDate)
        }
        .onChange(of: selectedDate) {
            let selectedMonth = monthStart(for: selectedDate)
            if selectedMonth != displayedMonth {
                displayedMonth = selectedMonth
            }
        }
        .onChange(of: displayedMonth) {
            loadDisplayedMonthActivityIfNeeded(for: displayedMonth)
        }
        .onChange(of: selectedStatsDate) {
            loadStatsIfNeeded()
        }
        .onChange(of: selectedScreenTab) {
            loadStatsIfNeeded()
        }
        .onChange(of: picoPlusStore.capabilities) {
            if picoPlusStore.capabilities.canAccessHistoricalDailySnapshots {
                loadSelectedSnapshotIfNeeded(for: selectedDate)
            }
            loadStatsIfNeeded()
        }
        .overlay {
            if isFocusGoalSheetPresented {
                DailyFocusGoalEditorModal(
                    currentGoalMinutes: dailyFocusGoalMinutes,
                    isSaving: isSavingFocusGoal,
                    notice: focusGoalNotice,
                    cancel: dismissFocusGoalEditor,
                    save: saveDailyFocusGoal
                )
                .padding(.horizontal, PicoSpacing.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    PicoColors.textPrimary.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissFocusGoalEditor()
                        }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.18), value: isFocusGoalSheetPresented)
    }

    private var header: some View {
        VStack(spacing: PicoSpacing.compact) {
            HStack {
                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    PicoIcon(.xMarkRegular, size: 19)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close calendar"))
            }

            screenTabs
        }
    }

    private var screenTabs: some View {
        HStack(spacing: PicoSpacing.compact) {
            ForEach(DailySnapshotScreenTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedScreenTab = tab
                    }
                } label: {
                    Text(tab.label)
                        .font(PicoTypography.largePill)
                        .foregroundStyle(selectedScreenTab == tab ? PicoColors.textPrimary : PicoColors.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PicoSpacing.compact)
                        .background(selectedScreenTab == tab ? PicoColors.surface : Color.clear)
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PicoSpacing.tiny)
        .background(PicoColors.softSurface)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
    }

    private var calendarTab: some View {
        VStack(spacing: PicoSpacing.section) {
            DailySnapshotCalendarHero(
                selectedDate: selectedDate,
                snapshot: selectedSnapshot,
                mode: heroMode,
                isLoading: loadState == .loading,
                isLocked: selectedDayRequiresPlus,
                notice: selectedDayRequiresPlus ? picoPlusStore.notice : notice,
                afterUnlock: loadSelectedSnapshotAfterPlusUnlock
            )

            heroModePills

            calendarPanel
        }
    }

    @ViewBuilder
    private var statsTab: some View {
        if isStatsLocked {
            DailyFocusStatsLockedPage(afterUnlock: loadStatsAfterPlusUnlock)
        } else {
            DailyFocusStatsPage(
                selectedDate: selectedStatsDate,
                distribution: selectedFocusDistribution,
                dailyGoalMinutes: dailyFocusGoalMinutes,
                isLoading: statsLoadState == .loading,
                notice: statsNotice,
                canGoToNextDay: canGoToNextStatsDay,
                isSavingFocusGoal: isSavingFocusGoal,
                previousDayAction: { moveSelectedStatsDay(by: -1) },
                nextDayAction: { moveSelectedStatsDay(by: 1) },
                editFocusGoalAction: presentFocusGoalEditor
            )
        }
    }

    private var heroModePills: some View {
        HStack(spacing: PicoSpacing.compact) {
            ForEach(DailySnapshotHeroMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        heroMode = mode
                    }
                } label: {
                    HStack(spacing: PicoSpacing.compact) {
                        DailySnapshotAssetIcon(name: mode.iconName, size: 20)

                        Text(mode.label)
                            .font(PicoTypography.largePill)
                            .foregroundStyle(PicoColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PicoSpacing.iconTextGap)
                        .background(PicoColors.surface)
                        .clipShape(Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(heroMode == mode ? PicoColors.primary : PicoColors.border, lineWidth: heroMode == mode ? 1.5 : 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendarPanel: some View {
        VStack(spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                Button {
                    moveDisplayedMonth(by: -1)
                } label: {
                    PicoIcon(.chevronLeftRegular, size: 18)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Previous month"))

                Spacer(minLength: 0)

                VStack(spacing: PicoSpacing.tiny) {
                    Text(displayedMonthTitle)
                        .font(PicoTypography.compactTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                Spacer(minLength: 0)

                Button {
                    moveDisplayedMonth(by: 1)
                } label: {
                    PicoIcon(.chevronRightRegular, size: 18)
                        .foregroundStyle(canGoToNextMonth ? PicoColors.textPrimary : PicoColors.textMuted)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNextMonth)
                .accessibilityLabel(Text("Next month"))
            }

            HStack(spacing: 0) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, dayLabel in
                    Text(dayLabel)
                        .font(PicoTypography.captionSemibold)
                        .foregroundStyle(PicoColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: PicoSpacing.compact) {
                ForEach(monthDays) { day in
                    DailySnapshotCalendarDayCell(day: day) {
                        guard let date = day.date, !day.isFuture else { return }
                        selectedDate = date
                        loadSelectedSnapshotIfNeeded(for: date)
                    }
                }
            }
        }
        .padding(PicoSpacing.standard)
        .background(PicoCalendarStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: PicoSpacing.compact), count: 7)
    }

    private func makeMonthDays() -> [DailySnapshotCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyDays = max(0, firstWeekday - 1)
        let monthDayCount = dayRange.count
        let occupiedCells = leadingEmptyDays + monthDayCount
        let trailingEmptyDays = (7 - occupiedCells % 7) % 7
        let totalCells = max(35, occupiedCells + trailingEmptyDays)

        return (0..<totalCells).map { index in
            let dayNumber = index - leadingEmptyDays + 1
            guard dayNumber >= 1, dayNumber <= monthDayCount,
                  let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthInterval.start) else {
                return DailySnapshotCalendarDay.placeholder(index: index, month: monthInterval.start)
            }

            let snapshotDay = DailySnapshotDay(date: date, calendar: calendar)
            let hasFocus = (focusActivityByDay[snapshotDay] ?? false)
                || (snapshotsByDay[snapshotDay]?.hasFocusActivity == true)
            return DailySnapshotCalendarDay(
                id: snapshotDay.rawValue,
                date: date,
                dayNumber: dayNumber,
                snapshot: snapshotsByDay[snapshotDay],
                hasFocus: hasFocus,
                isSelected: snapshotDay == selectedSnapshotDay,
                isFuture: calendar.startOfDay(for: date) > maximumDate,
                isPastNoCatches: calendar.startOfDay(for: date) < maximumDate
                    && !hasFocus
            )
        }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func moveDisplayedMonth(by offset: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        let month = min(monthStart(for: nextMonth), monthStart(for: maximumDate))
        displayedMonth = month
    }

    private func moveSelectedStatsDay(by offset: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: offset, to: selectedStatsDate) else { return }
        selectedStatsDate = min(calendar.startOfDay(for: nextDate), maximumDate)
    }

    private func loadDisplayedMonthActivityIfNeeded(for month: Date) {
        let monthKey = DailySnapshotDay(date: monthStart(for: month), calendar: calendar)
        guard !loadedFocusActivityMonths.contains(monthKey),
              !loadingFocusActivityMonths.contains(monthKey),
              let range = snapshotDayRange(for: month) else {
            return
        }

        loadingFocusActivityMonths.insert(monthKey)

        Task {
            await loadDisplayedMonthActivity(monthKey: monthKey, startDay: range.startDay, endDay: range.endDay)
        }
    }

    private func snapshotDayRange(for month: Date) -> (startDay: DailySnapshotDay, endDay: DailySnapshotDay)? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let lastDay = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end) else {
            return nil
        }

        return (
            DailySnapshotDay(date: monthInterval.start, calendar: calendar),
            DailySnapshotDay(date: min(lastDay, maximumDate), calendar: calendar)
        )
    }

    private func loadDisplayedMonthActivity(
        monthKey: DailySnapshotDay,
        startDay: DailySnapshotDay,
        endDay: DailySnapshotDay
    ) async {
        do {
            let activity = try await fetchFocusActivityAction(startDay, endDay)

            for dayActivity in activity {
                focusActivityByDay[dayActivity.snapshotDay] = dayActivity.hasFocus
            }
            loadedFocusActivityMonths.insert(monthKey)
            loadingFocusActivityMonths.remove(monthKey)
        } catch {
            loadingFocusActivityMonths.remove(monthKey)
        }
    }

    private func loadSelectedSnapshotIfNeeded(for date: Date) {
        let day = DailySnapshotDay(date: date, calendar: calendar)
        guard picoPlusStore.capabilities.canAccessDailySnapshot(isPastDay: isPastDay(date)) else {
            loadState = .loaded
            notice = nil
            return
        }

        guard snapshotByDay[day] == nil else {
            loadState = .loaded
            notice = nil
            return
        }

        Task {
            await loadSelectedSnapshot(day: day)
        }
    }

    private func loadSelectedSnapshot(day: DailySnapshotDay) async {
        loadState = .loading
        notice = nil

        do {
            let snapshot = try await fetchSnapshotAction(day)
            guard day == selectedSnapshotDay else { return }

            if let snapshot {
                snapshotByDay[snapshot.snapshotDay] = snapshot
                focusActivityByDay[snapshot.snapshotDay] = snapshot.hasFocusActivity
            } else {
                focusActivityByDay[day] = false
            }
            loadState = .loaded
        } catch {
            guard day == selectedSnapshotDay else { return }
            loadState = .failed
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func isPastDay(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < maximumDate
    }

    private func loadSelectedSnapshotAfterPlusUnlock() {
        if picoPlusStore.capabilities.canAccessDailySnapshot(isPastDay: isPastDay(selectedDate)) {
            loadSelectedSnapshotIfNeeded(for: selectedDate)
        }
    }

    private func loadStatsAfterPlusUnlock() {
        loadStatsIfNeeded()
    }

    private func loadStatsIfNeeded() {
        guard selectedScreenTab == .stats, picoPlusStore.capabilities.isPlusActive else { return }
        loadDailyFocusGoalIfNeeded()
        loadSelectedStatsDistributionIfNeeded(for: selectedStatsDate)
    }

    private func loadSelectedStatsDistributionIfNeeded(for date: Date) {
        let day = DailySnapshotDay(date: date, calendar: calendar)
        let isCurrentDay = day == DailySnapshotDay(date: maximumDate, calendar: calendar)
        guard (focusDistributionByDay[day] == nil || isCurrentDay),
              !loadingFocusDistributionDays.contains(day) else {
            statsLoadState = .loaded
            statsNotice = nil
            return
        }

        loadingFocusDistributionDays.insert(day)

        Task {
            await loadSelectedStatsDistribution(day: day)
        }
    }

    private func loadSelectedStatsDistribution(day: DailySnapshotDay) async {
        statsLoadState = .loading
        statsNotice = nil

        do {
            let distribution = try await fetchFocusDistributionAction(day)
            loadingFocusDistributionDays.remove(day)
            guard day == selectedStatsDay else { return }
            focusDistributionByDay[day] = distribution
            focusActivityByDay[day] = distribution.totalFocusedSeconds > 0 || distribution.metrics.totalFocusSessions > 0
            statsLoadState = .loaded
        } catch {
            loadingFocusDistributionDays.remove(day)
            guard day == selectedStatsDay else { return }
            statsLoadState = .failed
            statsNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadDailyFocusGoalIfNeeded() {
        guard !isLoadingFocusGoal else { return }
        isLoadingFocusGoal = true
        focusGoalNotice = nil

        Task {
            do {
                dailyFocusGoalMinutes = try await fetchDailyFocusGoalAction()
                isLoadingFocusGoal = false
            } catch {
                isLoadingFocusGoal = false
                focusGoalNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func presentFocusGoalEditor() {
        focusGoalNotice = nil
        isFocusGoalSheetPresented = true
    }

    private func dismissFocusGoalEditor() {
        guard !isSavingFocusGoal else { return }
        isFocusGoalSheetPresented = false
    }

    private func saveDailyFocusGoal(minutes: Int?) async {
        guard !isSavingFocusGoal else { return }
        isSavingFocusGoal = true
        focusGoalNotice = nil
        defer { isSavingFocusGoal = false }

        do {
            dailyFocusGoalMinutes = try await updateDailyFocusGoalAction(minutes)
            isFocusGoalSheetPresented = false
        } catch {
            focusGoalNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct DailySnapshotCalendarDay: Identifiable {
    let id: String
    let date: Date?
    let dayNumber: Int?
    let snapshot: DailyVillageSnapshot?
    let hasFocus: Bool
    let isSelected: Bool
    let isFuture: Bool
    let isPastNoCatches: Bool

    static func placeholder(index: Int, month: Date) -> DailySnapshotCalendarDay {
        DailySnapshotCalendarDay(
            id: "placeholder-\(month.timeIntervalSince1970)-\(index)",
            date: nil,
            dayNumber: nil,
            snapshot: nil,
            hasFocus: false,
            isSelected: false,
            isFuture: false,
            isPastNoCatches: false
        )
    }
}

private struct DailySnapshotCalendarDayCell: View {
    let day: DailySnapshotCalendarDay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if let dayNumber = day.dayNumber {
                    Text("\(dayNumber)")
                        .font(PicoTypography.captionSemibold)
                        .foregroundStyle(dayTextColor)
                        .monospacedDigit()

                    DailySnapshotBucketImage(isFilled: day.hasFocus)
                        .frame(height: PicoCalendarStyle.dayBucketHeight)
                        .opacity(bucketOpacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.dayCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PicoCalendarStyle.dayCornerRadius, style: .continuous)
                    .stroke(cellBorder, lineWidth: day.isSelected ? 1.5 : 1)
                    .opacity(day.dayNumber == nil ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(day.dayNumber == nil || day.isFuture)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayTextColor: Color {
        if day.isFuture || day.isPastNoCatches {
            return PicoColors.textMuted
        }

        return PicoColors.textPrimary
    }

    private var bucketOpacity: Double {
        if day.isFuture {
            return PicoCalendarStyle.inactiveDayOpacity
        }

        return day.hasFocus ? 1 : PicoCalendarStyle.emptyDayOpacity
    }

    private var cellBackground: Color {
        day.isSelected ? PicoCalendarStyle.selectedDayBackground : Color.clear
    }

    private var cellBorder: Color {
        day.isSelected ? PicoCalendarStyle.selectedDayBorder : Color.clear
    }

    private var accessibilityLabel: Text {
        guard let date = day.date else { return Text("Empty calendar cell") }
        let status = day.hasFocus ? "focus logged" : "no focus"
        return Text("\(date.formatted(.dateTime.month().day().year())), \(status)")
    }
}

private struct DailySnapshotBucketImage: View {
    let isFilled: Bool

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "shippingbox")
                    .font(PicoTypography.symbol(size: 20, weight: .semibold))
                    .foregroundStyle(PicoColors.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        let assetName = isFilled ? "Bucket" : "Empty_Bucket"
        return [
            "Icons/\(assetName)",
            "Icons/\(assetName).png",
            assetName,
            "\(assetName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct DailySnapshotAssetIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles")
                    .font(PicoTypography.symbol(size: size * 0.64, weight: .semibold))
                    .foregroundStyle(PicoColors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        [
            "Icons/\(name)",
            "Icons/\(name).png",
            name,
            "\(name).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct DailySnapshotCalendarHero: View {
    let selectedDate: Date
    let snapshot: DailyVillageSnapshot?
    let mode: DailySnapshotHeroMode
    let isLoading: Bool
    let isLocked: Bool
    let notice: String?
    let afterUnlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: PicoSpacing.tiny) {
                Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(PicoTypography.captionSemibold)
                    .foregroundStyle(PicoColors.textSecondary)
            }

            ZStack {
                if isLocked {
                    DailySnapshotPlusLockedHeroContent(afterUnlock: afterUnlock)
                } else {
                    switch mode {
                    case .bonds:
                        DailySnapshotBondsHeroContent(snapshot: snapshot)
                    case .fish:
                        DailySnapshotFishHeroContent(snapshot: snapshot)
                    }
                }

                if isLoading && !isLocked {
                    loadingOverlay
                }
            }
            .padding(.top, PicoSpacing.iconTextGap)

            if let notice, !isLoading {
                Label {
                    Text(notice)
                        .font(PicoTypography.caption)
                        .lineLimit(2)
                } icon: {
                    PicoIcon(.infoRegular, size: 15)
                }
                .foregroundStyle(PicoColors.textSecondary)
                .padding(.top, PicoSpacing.standard)
            }
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.vertical, PicoSpacing.standard)
        .frame(maxWidth: PicoCalendarStyle.heroCardMaxWidth)
        .frame(minHeight: PicoCalendarStyle.heroCardMinHeight)
        .background(PicoCalendarStyle.heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCalendarStyle.cardCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: PicoSpacing.compact) {
            ProgressView()
                .tint(PicoColors.primary)

            Text("Loading day")
                .font(PicoTypography.captionSemibold)
                .foregroundStyle(PicoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PicoCalendarStyle.heroBackground.opacity(0.88))
    }
}

private struct DailyFocusStatsLockedPage: View {
    let afterUnlock: () -> Void

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            VStack(spacing: PicoSpacing.standard) {
                Text("Stats")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)

                Text("Track your focus goals and daily time distribution with Plus.")
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PicoPlusCTAButton(
                    title: "Unlock Stats",
                    size: .regular,
                    source: .calendarView(placement: .calendarView),
                    afterPresentation: afterUnlock
                )
            }
            .padding(PicoSpacing.section)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 260)
            .background(PicoColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous)
                    .stroke(PicoColors.border, lineWidth: 1)
            }
        }
    }
}

private struct DailyFocusStatsPage: View {
    let selectedDate: Date
    let distribution: DailyFocusDistribution
    let dailyGoalMinutes: Int?
    let isLoading: Bool
    let notice: String?
    let canGoToNextDay: Bool
    let isSavingFocusGoal: Bool
    let previousDayAction: () -> Void
    let nextDayAction: () -> Void
    let editFocusGoalAction: () -> Void

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            dayNavigation

            DailySnapshotFocusHeroContent(
                metrics: distribution.metrics,
                dailyGoalMinutes: dailyGoalMinutes,
                isSavingGoal: isSavingFocusGoal,
                editGoalAction: editFocusGoalAction
            )

            DailyFocusDistributionChart(distribution: distribution)
                .overlay {
                    if isLoading {
                        loadingOverlay
                    }
                }

            if let notice, !isLoading {
                Label {
                    Text(notice)
                        .font(PicoTypography.caption)
                        .lineLimit(2)
                } icon: {
                    PicoIcon(.infoRegular, size: 15)
                }
                .foregroundStyle(PicoColors.textSecondary)
            }
        }
    }

    private var dayNavigation: some View {
        HStack(spacing: PicoSpacing.compact) {
            Button(action: previousDayAction) {
                PicoIcon(.chevronLeftRegular, size: 18)
                    .foregroundStyle(PicoColors.textPrimary)
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous stats day"))

            VStack(spacing: PicoSpacing.tiny) {
                Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(PicoTypography.primaryLabel)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .frame(maxWidth: .infinity)

            Button(action: nextDayAction) {
                PicoIcon(.chevronRightRegular, size: 18)
                    .foregroundStyle(canGoToNextDay ? PicoColors.textPrimary : PicoColors.textMuted)
                    .frame(width: 36, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(!canGoToNextDay)
            .accessibilityLabel(Text("Next stats day"))
        }
        .padding(.horizontal, PicoSpacing.compact)
        .padding(.vertical, PicoSpacing.tiny)
    }

    private var loadingOverlay: some View {
        VStack(spacing: PicoSpacing.compact) {
            ProgressView()
                .tint(PicoColors.primary)

            Text("Loading stats")
                .font(PicoTypography.captionSemibold)
                .foregroundStyle(PicoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PicoColors.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
    }
}

private struct DailyFocusDistributionChart: View {
    let distribution: DailyFocusDistribution

    private var totalFocusedText: AttributedString {
        var text = AttributedString("Total focused time: \(Self.formattedDuration(distribution.totalFocusedSeconds))")
        if let range = text.range(of: Self.formattedDuration(distribution.totalFocusedSeconds)) {
            text[range].foregroundColor = PicoColors.primary
        }
        return text
    }

    private var maxFocusedMinutes: Double {
        distribution.buckets
            .map { Double(max(0, $0.focusedSeconds)) / 60.0 }
            .max() ?? 0
    }

    private var axisMaximum: Double {
        max(75, ceil(maxFocusedMinutes / 15.0) * 15.0)
    }

    private var yTicks: [Int] {
        stride(from: Int(axisMaximum), through: 0, by: -15).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            Text("Time distribution")
                .font(PicoTypography.compactTitle)
                .foregroundStyle(PicoColors.textPrimary)

            VStack(spacing: PicoSpacing.compact) {
                chartArea
                    .frame(height: 182)

                xAxis
            }
        }
        .padding(PicoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PicoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Focused time distribution"))
        .accessibilityValue(Text(Self.formattedDuration(distribution.totalFocusedSeconds)))
    }

    private var chartArea: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: PicoSpacing.tiny) {
                yAxisLabels(height: proxy.size.height)

                ZStack(alignment: .bottom) {
                    gridLines(height: proxy.size.height)

                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(distribution.buckets) { bucket in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(PicoColors.primary.opacity(0.88))
                                .frame(height: barHeight(for: bucket, chartHeight: proxy.size.height))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func yAxisLabels(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(yTicks, id: \.self) { tick in
                Text(tick == 0 ? "0 M" : "\(tick)")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textMuted)
                    .position(x: 18, y: yPosition(for: tick, height: height))
            }
        }
        .frame(width: 38, height: height)
    }

    private func gridLines(height: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(yTicks, id: \.self) { tick in
                    Rectangle()
                        .fill(PicoColors.border.opacity(0.72))
                        .frame(width: proxy.size.width, height: 1)
                        .position(x: proxy.size.width / 2, y: yPosition(for: tick, height: height))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var xAxis: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 38)

            HStack {
                Text("00:00")
                Spacer(minLength: 0)
                Text("06:00")
                Spacer(minLength: 0)
                Text("12:00")
                Spacer(minLength: 0)
                Text("18:00")
                Spacer(minLength: 0)
                Text("23:00")
            }
            .font(PicoTypography.caption)
            .foregroundStyle(PicoColors.textMuted)
        }
    }

    private func yPosition(for tick: Int, height: CGFloat) -> CGFloat {
        let value = min(max(Double(tick), 0), axisMaximum)
        return height - (CGFloat(value / axisMaximum) * height)
    }

    private func barHeight(for bucket: DailyFocusDistributionBucket, chartHeight: CGFloat) -> CGFloat {
        let minutes = Double(max(0, bucket.focusedSeconds)) / 60.0
        guard minutes > 0 else { return 0 }
        return max(4, CGFloat(minutes / axisMaximum) * chartHeight)
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        let minutes = max(0, Int(ceil(Double(seconds) / 60.0)))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0, remainingMinutes > 0 {
            return "\(hours) hours \(remainingMinutes) mins"
        }

        if hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(remainingMinutes) mins"
    }
}

private struct DailySnapshotFocusHeroContent: View {
    let metrics: DailyFocusMetrics
    let dailyGoalMinutes: Int?
    let isSavingGoal: Bool
    let editGoalAction: () -> Void

    private var focusedMinutes: Int {
        let seconds = max(0, metrics.totalFocusedSeconds)
        return seconds == 0 ? 0 : Int(ceil(Double(seconds) / 60.0))
    }

    private var remainingGoalMinutes: Int? {
        guard let dailyGoalMinutes else { return nil }
        return max(dailyGoalMinutes - focusedMinutes, 0)
    }

    private var progressFraction: CGFloat {
        guard let dailyGoalMinutes, dailyGoalMinutes > 0 else { return 0 }
        return min(1, CGFloat(focusedMinutes) / CGFloat(dailyGoalMinutes))
    }

    private var progressValueText: String {
        guard let dailyGoalMinutes else {
            return "\(Self.formattedMinutes(focusedMinutes)) / Set goal"
        }

        return "\(Self.formattedMinutes(focusedMinutes)) / \(Self.formattedMinutes(dailyGoalMinutes))"
    }

    private var focusedValueText: String {
        Self.formattedMinutes(focusedMinutes)
    }

    private var goalValueText: String {
        guard let dailyGoalMinutes else { return "/ Set goal" }
        return "/ \(Self.formattedMinutes(dailyGoalMinutes))"
    }

    private var remainingText: String {
        guard let remainingGoalMinutes else { return "Set daily goal" }
        guard remainingGoalMinutes > 0 else { return "Goal met" }
        return "\(Self.formattedMinutes(remainingGoalMinutes)) left"
    }

    private var progressAccessibilityText: String {
        guard let dailyGoalMinutes else {
            return "\(Self.formattedMinutes(focusedMinutes)) focused. Set daily focus goal."
        }

        if let remainingGoalMinutes, remainingGoalMinutes > 0 {
            return "\(Self.formattedMinutes(focusedMinutes)) focused out of \(Self.formattedMinutes(dailyGoalMinutes)). \(Self.formattedMinutes(remainingGoalMinutes)) left."
        }

        return "\(Self.formattedMinutes(focusedMinutes)) focused out of \(Self.formattedMinutes(dailyGoalMinutes)). Goal met."
    }

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            focusProgressCard

            sessionMetricsCard
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var focusProgressCard: some View {
        Button(action: editGoalAction) {
            VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                HStack(spacing: PicoSpacing.compact) {
                    Text("Focus time")
                        .font(PicoTypography.compactTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: PicoSpacing.compact)

                    if isSavingGoal {
                        ProgressView()
                            .tint(PicoColors.primary)
                            .scaleEffect(0.76)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: PicoSpacing.compact) {
                    HStack(alignment: .lastTextBaseline, spacing: PicoSpacing.tiny) {
                        Text(focusedValueText)
                            .font(PicoTypography.durationValue)
                            .foregroundStyle(PicoColors.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(goalValueText)
                            .font(PicoTypography.captionSemibold)
                            .foregroundStyle(PicoColors.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: PicoSpacing.compact)

                    Text(remainingText)
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(PicoColors.softSurface)

                        Capsule(style: .continuous)
                            .fill(PicoColors.primary)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 10)
                .opacity(dailyGoalMinutes == nil ? 0.42 : 1)
            }
            .padding(PicoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSavingGoal)
        .background(PicoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
        .accessibilityLabel(Text("Focus goal"))
        .accessibilityValue(Text(progressAccessibilityText))
        .accessibilityHint(Text("Opens daily focus goal editor"))
    }

    private var sessionMetricsCard: some View {
        VStack(spacing: PicoSpacing.standard) {
            Text("Sessions")
                .font(PicoTypography.compactTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: sessionMetricColumns, spacing: PicoSpacing.standard) {
                ForEach(sessionMetricItems, id: \.label) { item in
                    DailySnapshotFocusMetricPill(
                        label: item.label,
                        value: item.value
                    )
                }
            }
        }
        .padding(PicoSpacing.cardPadding)
        .frame(maxWidth: .infinity)
        .background(PicoColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCalendarStyle.panelCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
    }

    private var completedFocusSessions: Int {
        max(metrics.totalFocusSessions - metrics.sessionsInterrupted, 0)
    }

    private var sessionMetricItems: [(label: String, value: Int)] {
        [
            ("Completed", completedFocusSessions),
            ("Interrupted", metrics.sessionsInterrupted),
            ("Solo", metrics.soloFocusSessions),
            ("With friends", metrics.groupFocusSessions)
        ]
    }

    private var sessionMetricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: PicoSpacing.standard, alignment: .leading), count: 2)
    }

    private static func formattedMinutes(_ minutes: Int) -> String {
        let clampedMinutes = max(0, minutes)
        let hours = clampedMinutes / 60
        let remainingMinutes = clampedMinutes % 60

        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(remainingMinutes)m"
    }
}

private struct DailySnapshotFocusMetricPill: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
            Text("\(max(0, value))")
                .font(PicoTypography.sectionTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(label)
                .font(PicoTypography.captionSemibold)
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
    }
}

private struct DailyFocusGoalEditorModal: View {
    @State private var draftMinutes: String
    let currentGoalMinutes: Int?
    let isSaving: Bool
    let notice: String?
    let cancel: () -> Void
    let save: (Int?) async -> Void

    init(
        currentGoalMinutes: Int?,
        isSaving: Bool,
        notice: String?,
        cancel: @escaping () -> Void,
        save: @escaping (Int?) async -> Void
    ) {
        self.currentGoalMinutes = currentGoalMinutes
        self.isSaving = isSaving
        self.notice = notice
        self.cancel = cancel
        self.save = save
        _draftMinutes = State(initialValue: currentGoalMinutes.map(String.init) ?? "")
    }

    private var parsedGoalMinutes: Int? {
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var validationMessage: String? {
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let minutes = Int(trimmed) else {
            return "Enter whole minutes."
        }
        guard DailyFocusGoal.minimumMinutes...DailyFocusGoal.maximumMinutes ~= minutes else {
            return "Choose 1 to 1440 minutes."
        }
        return nil
    }

    private var canSave: Bool {
        !isSaving && validationMessage == nil
    }

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            HStack(alignment: .top, spacing: PicoSpacing.standard) {
                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text("Daily focus goal")
                        .font(PicoTypography.cardTitle)
                        .foregroundStyle(PicoColors.textPrimary)

                    Text("Set the minutes you want to focus each day.")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: cancel) {
                    PicoIcon(.xMarkRegular, size: 16)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(PicoColors.softSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel(Text("Close daily focus goal editor"))
            }

            VStack(spacing: PicoSpacing.standard) {
                TextField("Minutes", text: $draftMinutes)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .font(PicoTypography.largeValue)
                    .foregroundStyle(PicoColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .padding(.horizontal, PicoSpacing.standard)
                    .frame(height: 72)
                    .background(PicoColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                            .stroke(PicoColors.border, lineWidth: 1)
                    }

                if let validationMessage {
                    Text(validationMessage)
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let notice {
                    Text(notice)
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: PicoSpacing.compact) {
                Button {
                    cancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PicoSecondaryButtonStyle())
                .disabled(isSaving)

                Button {
                    Task {
                        await save(parsedGoalMinutes)
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(PicoColors.surface)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(parsedGoalMinutes == nil ? "Clear" : "Save")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PicoPrimaryButtonStyle())
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.bottom, PicoSpacing.cardPadding)
        .padding(.top, PicoSpacing.cardPadding)
        .frame(maxWidth: 360)
        .background(PicoColors.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.sheetCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PicoCreamCardStyle.sheetCornerRadius, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        }
        .shadow(color: PicoColors.textPrimary.opacity(0.14), radius: 24, x: 0, y: 14)
        .onChange(of: currentGoalMinutes) {
            draftMinutes = currentGoalMinutes.map(String.init) ?? ""
        }
    }
}

private struct DailySnapshotPlusLockedHeroContent: View {
    let afterUnlock: () -> Void

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            Spacer(minLength: 0)

            Text("Track your progress with plus")
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            PicoPlusCTAButton(
                title: "Unlock with Plus",
                size: .pill,
                source: .calendarView(placement: .calendarView),
                afterPresentation: afterUnlock
            )
                .accessibilityHint(Text("Pico Plus unlocks past calendar day details."))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PicoCalendarStyle.heroContentHeight)
    }
}

private struct DailySnapshotBondsHeroContent: View {
    let snapshot: DailyVillageSnapshot?
    @State private var selectedBondIndex = 0

    private var visitors: [DailyVillageSnapshotVisitor] {
        (snapshot?.visitors ?? []).sorted {
            if $0.bondLevel != $1.bondLevel {
                return $0.bondLevel > $1.bondLevel
            }

            return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
        }
    }

    var body: some View {
        if visitors.isEmpty {
            DailySnapshotHeroEmptyState(
                title: "No bonds",
                message: showsBondEmptyStateMessage ? "No villagers bonded on this day." : nil,
                image: DailySnapshotAssetIcon(name: "Scarf_Green", size: 72)
            )
        } else {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedBondIndex) {
                    ForEach(visitors.indices, id: \.self) { index in
                        DailySnapshotBondHeroItem(visitor: visitors[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                DailySnapshotCarouselIndicator(
                    count: visitors.count,
                    selectedIndex: selectedBondIndex
                )
            }
            .frame(height: PicoCalendarStyle.heroContentHeight)
            .onChange(of: visitors.count) {
                selectedBondIndex = min(selectedBondIndex, max(0, visitors.count - 1))
            }
        }
    }

    private var showsBondEmptyStateMessage: Bool {
        guard let snapshot else { return false }
        return snapshot.totalFocusSeconds <= 0 || snapshot.fishCaughtCount <= 0
    }
}

private struct DailySnapshotBondHeroItem: View {
    let visitor: DailyVillageSnapshotVisitor

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            DailySnapshotHappyAvatarView(
                config: visitor.profile.avatarConfig,
                scarf: AvatarScarf(bondLevel: visitor.bondLevel)
            )
            .frame(width: 156, height: 172)

            Text(visitor.profile.displayName)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(visitor.profile.displayName))
    }
}

private struct DailySnapshotFishHeroContent: View {
    let snapshot: DailyVillageSnapshot?
    @State private var selectedFishIndex = 0

    private var fishCounts: [FishCount] {
        (snapshot?.fishCounts ?? []).sorted {
            if $0.rarity.rarestFirstSortRank != $1.rarity.rarestFirstSortRank {
                return $0.rarity.rarestFirstSortRank < $1.rarity.rarestFirstSortRank
            }

            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }

            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        if fishCounts.isEmpty {
            DailySnapshotHeroEmptyState(
                title: "No fish",
                message: snapshot == nil ? nil : "No fish caught on this day.",
                image: DailySnapshotAssetIcon(name: "FishingPole_New", size: 78)
            )
        } else {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedFishIndex) {
                    ForEach(fishCounts.indices, id: \.self) { index in
                        DailySnapshotFishHeroCard(fishCount: fishCounts[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                DailySnapshotCarouselIndicator(
                    count: fishCounts.count,
                    selectedIndex: selectedFishIndex
                )
            }
            .frame(height: PicoCalendarStyle.heroContentHeight)
            .onChange(of: fishCounts.count) {
                selectedFishIndex = min(selectedFishIndex, max(0, fishCounts.count - 1))
            }
        }
    }
}

private struct DailySnapshotFishHeroCard: View {
    let fishCount: FishCount

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            DailySnapshotFishIcon(fishCount: fishCount, size: PicoCalendarStyle.heroIconSize)
                .frame(height: PicoCalendarStyle.heroIconSize)

            Text(fishCount.displayName)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            HStack(spacing: PicoSpacing.tiny) {
                DailySnapshotFishRarityBadge(fishCount: fishCount)
                DailySnapshotFishCountBadge(fishCount: fishCount)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(fishCount.displayName), \(fishCount.count) caught"))
    }
}

private struct DailySnapshotFishRarityBadge: View {
    let fishCount: FishCount

    private var style: PicoFishRarityStyle {
        fishCount.rarity.picoStyle
    }

    var body: some View {
        Text(fishCount.rarity.label)
            .font(PicoTypography.captionSemibold)
            .foregroundStyle(style.pillTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .padding(.vertical, 5)
            .background(style.pillBackgroundColor)
            .clipShape(Capsule(style: .continuous))
    }
}

private struct DailySnapshotFishCountBadge: View {
    let fishCount: FishCount

    var body: some View {
        Text("×\(fishCount.count)")
            .font(PicoTypography.captionSemibold)
            .foregroundStyle(PicoColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .monospacedDigit()
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .padding(.vertical, 5)
            .background(PicoCalendarStyle.heroBackground)
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(PicoColors.border, lineWidth: 1)
            }
    }
}

private struct DailySnapshotCarouselIndicator: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? PicoColors.primary : PicoColors.textMuted.opacity(0.34))
                        .frame(width: index == selectedIndex ? 7 : 5, height: index == selectedIndex ? 7 : 5)
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
    }
}

private struct DailySnapshotHappyAvatarView: View {
    let config: AvatarConfig
    let scarf: AvatarScarf?

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: DailySnapshotHappyAvatarScene(
                    size: proxy.size,
                    hat: config.selectedHat,
                    scarf: scarf
                ),
                options: [.allowsTransparency]
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .accessibilityHidden(true)
    }
}

private final class DailySnapshotHappyAvatarScene: SKScene {
    private static let idleActionKey = "daily-snapshot-happy-idle"

    private let hat: AvatarHat
    private let scarf: AvatarScarf?
    private var renderedSize: CGSize = .zero

    init(size: CGSize, hat: AvatarHat, scarf: AvatarScarf?) {
        self.hat = hat
        self.scarf = scarf
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        redrawIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redrawIfNeeded()
    }

    private func redrawIfNeeded() {
        guard size.width > 0, size.height > 0, size != renderedSize else { return }

        renderedSize = size
        removeAllChildren()

        let frames = AvatarHappyIdleFrames(hat: hat, scarf: scarf).layeredFrames
        let sprite = AvatarLayeredSpriteNode(frames: frames)
        let spriteSide = min(size.width, size.height)
        sprite.spriteSize = CGSize(width: spriteSide, height: spriteSide)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.runAnimation(
            with: frames,
            row: 0,
            timePerFrame: 0.10,
            key: Self.idleActionKey
        )
        addChild(sprite)
    }
}

private struct DailySnapshotFishIcon: View {
    let fishCount: FishCount
    let size: CGFloat

    var body: some View {
        Group {
            if let fishImage {
                Image(uiImage: fishImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: size * 0.58, weight: .semibold))
                    .foregroundStyle(fishCount.rarity.picoStyle.iconFallbackColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fishImage: UIImage? {
        var candidates = fishImageResourceCandidates(named: fishCount.assetName)
        for candidate in fishImageResourceCandidates(named: fishCount.seaCritterID.assetName) {
            candidates.appendIfMissing(candidate)
        }

        return candidates.lazy.compactMap { UIImage(named: $0) }.first
    }
}

private struct DailySnapshotHeroEmptyState<ImageContent: View>: View {
    let title: String
    let message: String?
    let image: ImageContent

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            image
                .frame(width: 68, height: 84)
                .opacity(PicoCalendarStyle.emptyDayOpacity)

            Text(title)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)

            if let message {
                Text(message)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PicoCalendarStyle.heroContentHeight)
    }
}

private struct HomeFocusBottomBar: View {
    let mode: StartFocusCTA.Mode
    let isLoadingBalance: Bool
    let balanceNotice: String?
    let incomingInviteCount: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            StartFocusCTA(
                mode: mode,
                incomingInviteCount: incomingInviteCount,
                isLoading: false,
                action: action
            )
        }
        .padding(.horizontal, 44)
        .padding(.top, PicoSpacing.compact)
        .padding(.bottom, PicoSpacing.compact)
        .background(
            PicoColors.appBackground
                .opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .topLeading) {
            if showsStatus {
                statusOverlay
                    .padding(.horizontal, 44)
                    .offset(y: -34)
            }
        }
    }

    private var showsStatus: Bool {
        isLoadingBalance || balanceNotice != nil
    }

    private var statusOverlay: some View {
        HStack(spacing: PicoSpacing.compact) {
            if isLoadingBalance {
                ProgressView()
                    .tint(PicoColors.primary)
            }

            if let balanceNotice {
                Text(balanceNotice)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, PicoSpacing.iconTextGap)
        .padding(.vertical, PicoSpacing.compact)
        .background(
            Capsule(style: .continuous)
                .fill(PicoColors.surface.opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        )
    }
}

private struct StartFocusCTA: View {
    enum Mode {
        case startFocus
        case viewFish
    }

    @StateObject private var reelHaptics = ReelHaptics()
    @State private var isReeling = false
    @State private var reelProgress: CGFloat = 0

    let mode: Mode
    let incomingInviteCount: Int
    let isLoading: Bool
    let action: () -> Void

    private let reelFillDuration: TimeInterval = 0.8

    private var title: String {
        switch mode {
        case .startFocus:
            "Start Focus"
        case .viewFish:
            "Reel it in!"
        }
    }

    var body: some View {
        Group {
            if mode == .viewFish {
                ctaLabel
                    .contentShape(Capsule(style: .continuous))
                    .onLongPressGesture(
                        minimumDuration: reelFillDuration,
                        maximumDistance: 48,
                        pressing: updateReelingState,
                        perform: completeReel
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        action()
                    }
            } else {
                Button(action: action) {
                    ctaLabel
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            stopReelingHaptics()
        }
    }

    private var ctaLabel: some View {
        VStack(spacing: 2) {
            if mode == .viewFish {
                Text("Hold down to pull")
                    .font(PicoTypography.caption)
                    .foregroundStyle(foregroundColor.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: PicoSpacing.compact) {
                Text(displayTitle)
                    .font(PicoTypography.actionTitle)

                if mode == .startFocus || mode == .viewFish {
                    FishingPoleCTAIcon()
                        .frame(width: 25, height: 25)
                        .accessibilityHidden(true)
                }

                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            if mode == .startFocus, incomingInviteCount > 0 {
                Text("\(incomingInviteCount) invite\(incomingInviteCount == 1 ? "" : "s") waiting")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textOnPrimary.opacity(0.86))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, PicoSpacing.section)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(background)
        .overlay(border)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
    }

    private var displayTitle: String {
        mode == .viewFish && isReeling ? "Reeling..." : title
    }

    private func updateReelingState(_ isPressing: Bool) {
        isReeling = isPressing
        if isPressing {
            reelHaptics.start()
        } else {
            stopReelingHaptics()
        }

        withAnimation(isPressing ? .linear(duration: reelFillDuration) : .easeOut(duration: 0.22)) {
            reelProgress = isPressing ? 1 : 0
        }
    }

    private func completeReel() {
        action()
        stopReelingHaptics()

        withAnimation(.easeOut(duration: 0.18)) {
            reelProgress = 0
            isReeling = false
        }
    }

    private func stopReelingHaptics() {
        reelHaptics.stop()
    }

    private var foregroundColor: Color {
        switch mode {
        case .startFocus:
            PicoColors.textOnPrimary
        case .viewFish:
            PicoColors.textOnPrimary
        }
    }

    private var background: some View {
        Group {
            if mode == .viewFish {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(reelBaseColor)

                        Rectangle()
                            .fill(reelFillColor)
                            .frame(width: proxy.size.width * reelProgress)
                    }
                    .clipShape(Capsule(style: .continuous))
                }
            } else {
                Capsule(style: .continuous)
                    .fill(PicoColors.primary)
            }
        }
    }

    private var border: some View {
        Capsule(style: .continuous)
            .stroke(
                mode == .viewFish
                    ? Color.clear
                    : Color.clear,
                lineWidth: 1
            )
    }

    private var shadowColor: Color {
        switch mode {
        case .startFocus:
            .clear
        case .viewFish:
            .clear
        }
    }

    private var reelBaseColor: Color {
        Color(hex: 0x54B8FF)
    }

    private var reelFillColor: Color {
        Color(hex: 0x2F9FEA)
    }
}

private struct FishingPoleCTAIcon: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: 22, weight: .semibold))
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/FishingPole_New",
            "Icons/FishingPole_New.png",
            "FishingPole_New",
            "FishingPole_New.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct SheetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StartFocusSheet: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep
    @Binding var isPresented: Bool
    @Binding var measuredHeight: CGFloat
    let usesContentSizedLayout: Bool
    @State private var multiplayerDurationSeconds = FocusStore.defaultDurationSeconds

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            sheetHeader

            if usesContentSizedLayout {
                VStack(spacing: PicoSpacing.standard) {
                    if usesPinnedSheetContent {
                        noticeText
                        sheetContent
                    } else {
                        sheetContent
                        noticeText
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if usesPinnedSheetContent {
                VStack(spacing: PicoSpacing.standard) {
                    noticeText
                    sheetContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: PicoSpacing.standard) {
                        sheetContent
                        noticeText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, PicoCreamCardStyle.contentPadding)
        .padding(.top, PicoSpacing.section)
        .padding(.bottom, PicoSpacing.section)
        .frame(maxHeight: usesContentSizedLayout ? nil : .infinity, alignment: .top)
        .background(PicoColors.appBackground.ignoresSafeArea())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightPreferenceKey.self) { height in
            guard usesContentSizedLayout, height > 0 else { return }
            let roundedHeight = ceil(height)
            guard abs(measuredHeight - roundedHeight) > 0.5 else { return }
            measuredHeight = roundedHeight
        }
        .task {
            await friendStore.loadFriends(for: sessionStore.session)
            await focusStore.refresh(for: sessionStore.session)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let lobbySession = focusStore.lobbySession {
            if lobbySession.mode == .solo {
                SoloFocusConfigSheetContent(session: lobbySession)
            } else if step == .multiplayerInviteMore {
                MultiplayerInviteFriendsSheetContent(
                    step: $step,
                    durationSeconds: .constant(clampedDurationSeconds(from: lobbySession.durationSeconds)),
                    buttonTitle: "Send invites"
                )
            } else {
                MultiplayerLobbySheetContent(
                    step: $step,
                    isPresented: $isPresented,
                    session: lobbySession
                )
            }
        } else {
            switch step {
            case .modePicker:
                FocusModePickerSheetContent(step: $step)
            case .soloConfig:
                SoloFocusConfigSheetContent(session: nil)
            case .multiplayerConfig:
                MultiplayerDurationSheetContent(
                    step: $step,
                    durationSeconds: $multiplayerDurationSeconds
                )
            case .multiplayerInviteMore:
                MultiplayerInviteFriendsSheetContent(
                    step: $step,
                    durationSeconds: $multiplayerDurationSeconds,
                    buttonTitle: "Send invites"
                )
            case .multiplayerLobby:
                MultiplayerLobbySheetContent(
                    step: $step,
                    isPresented: $isPresented,
                    session: nil
                )
            case .invites:
                IncomingFocusInvitesSheetContent()
            }
        }
    }

    @ViewBuilder
    private var noticeText: some View {
        if let notice = focusStore.notice {
            Text(notice)
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var usesPinnedSheetContent: Bool {
        guard focusStore.resultSession == nil else { return false }
        if focusStore.lobbySession != nil {
            return true
        }
        return step == .soloConfig
            || step == .multiplayerConfig
            || step == .multiplayerInviteMore
            || step == .multiplayerLobby
    }

    private var title: String {
        if focusStore.resultSession != nil {
            return "Focus Complete"
        }

        if step == .multiplayerInviteMore {
            return "Invite Friends"
        }

        if let lobbySession = focusStore.lobbySession {
            return lobbySession.mode == .solo ? "Solo Focus" : "Multiplayer"
        }

        switch step {
        case .modePicker:
            return "Start Focus"
        case .soloConfig:
            return "Solo Focus"
        case .multiplayerConfig, .multiplayerLobby:
            return "Multiplayer"
        case .multiplayerInviteMore:
            return "Invite Friends"
        case .invites:
            return "Invites"
        }
    }

    private var sheetHeader: some View {
        HStack {
            if showsBackButton {
                Button {
                    if step == .multiplayerInviteMore {
                        step = focusStore.lobbySession == nil ? .multiplayerConfig : .multiplayerLobby
                    } else {
                        step = .modePicker
                    }
                } label: {
                    PicoIcon(.chevronLeftRegular, size: 18)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
            } else {
                Spacer()
                    .frame(width: 36, height: 36)
            }

            Spacer()

            VStack(spacing: PicoSpacing.tiny) {
                Text(title)
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            Button {
                isPresented = false
            } label: {
                PicoIcon(.xMarkRegular, size: 18)
                    .foregroundStyle(PicoColors.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
    }

    private var showsBackButton: Bool {
        guard focusStore.resultSession == nil else { return false }
        if focusStore.lobbySession != nil {
            return step == .multiplayerInviteMore
        }
        return step != .modePicker
    }
}

private struct FocusModePickerSheetContent: View {
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep

    var body: some View {
        VStack(spacing: PicoSpacing.iconTextGap) {
            FocusModeRow(
                imageName: "Bucket",
                title: "Solo",
                titleFont: PicoTypography.body
            ) {
                step = .soloConfig
            }

            FocusModeRow(
                imageName: "Scarf_Green",
                title: "With friends",
                titleFont: PicoTypography.body
            ) {
                step = .multiplayerConfig
            }

            if !focusStore.incomingInvites.isEmpty {
                FocusModeRow(
                    imageName: "Letter",
                    title: "Invites",
                    isHighlighted: true
                ) {
                    step = .invites
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IncomingFocusInvitesSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            if focusStore.isLoadingInvites && focusStore.incomingInvites.isEmpty {
                HStack {
                    Text("Loading invites")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)

                    Spacer()

                    ProgressView()
                        .tint(PicoColors.primary)
                }
                .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
            } else if focusStore.incomingInvites.isEmpty {
                Text("No invites right now.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
            } else {
                ForEach(focusStore.incomingInvites) { invite in
                    IncomingFocusInviteSheetRow(invite: invite)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IncomingFocusInviteSheetRow: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let invite: FocusSessionInvite
    private let avatarColumnSize: CGFloat = 42
    private let avatarSize: CGFloat = 38

    var body: some View {
        inviteCardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
    }

    private var inviteCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(
                    config: invite.host.avatarConfig,
                    size: avatarSize,
                    scarf: scarf(for: invite.host.userID)
                )
                    .frame(width: avatarColumnSize, height: avatarColumnSize, alignment: .center)

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(invite.host.displayName)
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)

                    Text("@\(invite.host.username)")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                FocusDurationBadge(seconds: invite.session.durationSeconds)
            }

            Text("Invited you to a focus session")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(2)

            HStack(spacing: PicoSpacing.iconTextGap) {
                Button {
                    Task {
                        await focusStore.joinInvite(invite, for: sessionStore.session)
                    }
                } label: {
                    HStack {
                        Text("Accept")
                        if focusStore.activeInviteID == invite.id {
                            ProgressView()
                                .tint(PicoColors.textOnPrimary)
                        }
                    }
                }
                .buttonStyle(PicoPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(focusStore.activeInviteID != nil)

                Button {
                    Task {
                        await focusStore.declineInvite(invite, for: sessionStore.session)
                    }
                } label: {
                    Text("Decline")
                }
                .buttonStyle(PicoCreamBorderedButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(focusStore.activeInviteID != nil)
            }
        }
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func scarf(for userID: UUID) -> AvatarScarf? {
        villageStore.scarf(
            for: userID,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }
}

private struct FocusDurationBadge: View {
    let seconds: Int
    var imageName: String? = nil
    var imageFrameSize = CGSize(width: 18, height: 18)

    var body: some View {
        HStack(spacing: 6) {
            iconView

            Text(homeFormattedDurationMinutes(seconds))
                .font(PicoTypography.caption.monospacedDigit())
                .foregroundStyle(PicoColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(PicoCreamCardStyle.badgeBackground)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
        )
        .fixedSize()
    }

    @ViewBuilder
    private var iconView: some View {
        if let image {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: imageFrameSize.width, height: imageFrameSize.height)
        } else {
            PicoIcon(.clockRegular, size: 13)
                .foregroundStyle(PicoColors.primary)
        }
    }

    private var image: UIImage? {
        guard let imageName else { return nil }
        return [
            "Icons/\(imageName)",
            "Icons/\(imageName).png",
            imageName,
            "\(imageName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct FocusModeRow: View {
    let icon: PicoIconAsset?
    let imageName: String?
    let title: String
    let titleFont: Font
    var isHighlighted = false
    let action: () -> Void
    private let iconSize: CGFloat = 24
    private let iconFrameSize: CGFloat = 30
    private let chevronSize: CGFloat = 17

    init(
        icon: PicoIconAsset,
        title: String,
        titleFont: Font = PicoTypography.body.weight(.bold),
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.imageName = nil
        self.title = title
        self.titleFont = titleFont
        self.isHighlighted = isHighlighted
        self.action = action
    }

    init(
        imageName: String,
        title: String,
        titleFont: Font = PicoTypography.body.weight(.bold),
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = nil
        self.imageName = imageName
        self.title = title
        self.titleFont = titleFont
        self.isHighlighted = isHighlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.standard) {
                iconView

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(titleColor)
                }

                Spacer(minLength: 0)

                PicoIcon(.chevronRightRegular, size: chevronSize)
                    .foregroundStyle(chevronColor)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, PicoCreamCardStyle.sheetCardPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: PicoCreamCardStyle.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: iconFrameSize, height: iconFrameSize)
        } else if let icon {
            PicoIcon(icon, size: iconSize)
                .foregroundStyle(iconColor)
                .frame(width: iconFrameSize, height: iconFrameSize)
        }
    }

    private var image: UIImage? {
        guard let imageName else { return nil }
        return [
            "Icons/\(imageName)",
            "Icons/\(imageName).png",
            imageName,
            "\(imageName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }

    private var titleColor: Color {
        isHighlighted ? PicoColors.textOnPrimary : PicoColors.textPrimary
    }

    private var iconColor: Color {
        isHighlighted ? PicoColors.textOnPrimary : PicoColors.primary
    }

    private var chevronColor: Color {
        isHighlighted ? PicoColors.textOnPrimary.opacity(0.86) : PicoColors.textMuted
    }

    private var rowBackground: Color {
        isHighlighted ? PicoColors.primary : PicoCreamCardStyle.background
    }

    private var borderColor: Color {
        isHighlighted ? PicoColors.primary : PicoCreamCardStyle.border
    }
}

private enum FocusSheetActionIconPlacement {
    case leading
    case trailing
}

private struct SheetActionImageIcon: View {
    let imageName: String
    let frameSize: CGSize

    var body: some View {
        if let image {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    private var image: UIImage? {
        [
            "Icons/\(imageName)",
            "Icons/\(imageName).png",
            imageName,
            "\(imageName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct FocusSheetActionLabel: View {
    let title: String
    let icon: PicoIconAsset?
    let imageName: String?
    var placement: FocusSheetActionIconPlacement = .leading
    var showsProgress = false
    var progressTint: Color = PicoColors.textPrimary

    private let iconSize: CGFloat = 22
    private let iconFrameSize: CGFloat = 28
    private let imageFrameSize: CGSize?

    init(
        title: String,
        icon: PicoIconAsset,
        placement: FocusSheetActionIconPlacement = .leading,
        showsProgress: Bool = false,
        progressTint: Color = PicoColors.textPrimary
    ) {
        self.title = title
        self.icon = icon
        self.imageName = nil
        self.placement = placement
        self.showsProgress = showsProgress
        self.progressTint = progressTint
        self.imageFrameSize = nil
    }

    init(
        title: String,
        imageName: String,
        imageFrameSize: CGSize? = nil,
        placement: FocusSheetActionIconPlacement = .leading,
        showsProgress: Bool = false,
        progressTint: Color = PicoColors.textPrimary
    ) {
        self.title = title
        self.icon = nil
        self.imageName = imageName
        self.placement = placement
        self.showsProgress = showsProgress
        self.progressTint = progressTint
        self.imageFrameSize = imageFrameSize
    }

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            if placement == .leading {
                iconView
            }

            Text(title)

            if placement == .trailing {
                iconView
            }

            if showsProgress {
                ProgressView()
                    .tint(progressTint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var iconView: some View {
        if let image {
            let frameSize = imageFrameSize ?? CGSize(width: iconFrameSize, height: iconFrameSize)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: frameSize.width, height: frameSize.height)
        } else if let icon {
            PicoIcon(icon, size: iconSize)
                .frame(width: iconFrameSize, height: iconFrameSize)
        }
    }

    private var image: UIImage? {
        guard let imageName else { return nil }
        return [
            "Icons/\(imageName)",
            "Icons/\(imageName).png",
            imageName,
            "\(imageName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct FocusDurationSlider: View {
    @Binding var durationSeconds: Int
    let isDisabled: Bool

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(durationSeconds) },
            set: { durationSeconds = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: PicoSpacing.standard) {
            Text(homeFormattedDuration(durationSeconds))
                .font(PicoTypography.durationValue)
                .monospacedDigit()
                .foregroundStyle(PicoColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            PicoRangeSlider(
                value: sliderValue,
                bounds: Double(FocusStore.minimumDurationSeconds)...Double(FocusStore.maximumDurationSeconds),
                step: Double(5 * 60),
                isDisabled: isDisabled
            )
            .padding(.horizontal, PicoSpacing.standard)
        }
    }
}

private struct PicoRangeSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let isDisabled: Bool

    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - thumbSize, 1)
            let progress = CGFloat(normalizedProgress)
            let thumbX = usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(PicoCreamCardStyle.controlBackground)
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(PicoColors.primary)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)

                Circle()
                    .fill(PicoCreamCardStyle.background)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
                    )
                    .shadow(color: PicoShadow.raisedCardColor, radius: 6, x: 0, y: 3)
                    .offset(x: thumbX)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard !isDisabled else { return }
                        updateValue(at: gesture.location.x, usableWidth: usableWidth)
                    }
            )
        }
        .frame(height: thumbSize)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Duration"))
        .accessibilityValue(Text(homeFormattedDuration(Int(value.rounded()))))
        .accessibilityAdjustableAction { direction in
            guard !isDisabled else { return }
            switch direction {
            case .increment:
                value = snappedValue(value + step)
            case .decrement:
                value = snappedValue(value - step)
            @unknown default:
                break
            }
        }
    }

    private var normalizedProgress: Double {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        return (clampedValue - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }

    private func updateValue(at xPosition: CGFloat, usableWidth: CGFloat) {
        let progress = min(max(Double((xPosition - thumbSize / 2) / usableWidth), 0), 1)
        let rawValue = bounds.lowerBound + progress * (bounds.upperBound - bounds.lowerBound)
        value = snappedValue(rawValue)
    }

    private func snappedValue(_ rawValue: Double) -> Double {
        let steppedValue = (rawValue / step).rounded() * step
        return min(max(steppedValue, bounds.lowerBound), bounds.upperBound)
    }
}

private struct SoloFocusConfigSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @State private var durationSeconds = FocusStore.defaultDurationSeconds

    let session: FocusSession?

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            VStack(alignment: .center, spacing: PicoSpacing.standard) {
                Text("Duration")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textPrimary)

                FocusDurationSlider(durationSeconds: $durationSeconds, isDisabled: isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.sheetCardPadding,
                border: .clear
            )

            Button {
                Task {
                    await startSolo()
                }
            } label: {
                HStack {
                    Text("Start")
                    FishingPoleCTAIcon()
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)

                    if isBusy {
                        ProgressView()
                            .tint(PicoColors.textOnPrimary)
                    }
                }
            }
            .buttonStyle(PicoPrimaryButtonStyle())
            .disabled(isBusy || focusStore.hasPendingResultSync)
            .opacity(isBusy || focusStore.hasPendingResultSync ? 0.62 : 1)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            durationSeconds = clampedDurationSeconds(from: session?.durationSeconds ?? FocusStore.defaultDurationSeconds)
        }
        .onChange(of: session?.durationSeconds) {
            durationSeconds = clampedDurationSeconds(from: session?.durationSeconds ?? FocusStore.defaultDurationSeconds)
        }
    }

    private var isBusy: Bool {
        focusStore.isCreating || focusStore.isUpdatingConfig || focusStore.isStarting
    }

    private func startSolo() async {
        if focusStore.lobbySession?.mode != .solo {
            await focusStore.createLobby(mode: .solo, durationSeconds: durationSeconds, for: sessionStore.session)
        }

        guard let lobbySession = focusStore.lobbySession, lobbySession.mode == .solo else { return }

        if lobbySession.durationSeconds != durationSeconds {
            await focusStore.updateLobbyDuration(durationSeconds, for: sessionStore.session)
        }

        await focusStore.startLobbySession(for: sessionStore.session)
    }
}

private struct MultiplayerDurationSheetContent: View {
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep
    @Binding var durationSeconds: Int

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            VStack(alignment: .center, spacing: PicoSpacing.standard) {
                Text("Duration")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textPrimary)

                FocusDurationSlider(durationSeconds: $durationSeconds, isDisabled: focusStore.hasPendingResultSync)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.sheetCardPadding,
                border: .clear
            )

            Button {
                step = .multiplayerInviteMore
            } label: {
                FocusSheetActionLabel(
                    title: "Invite friends",
                    imageName: "Envolope",
                    imageFrameSize: CGSize(width: 27, height: 22)
                )
            }
            .buttonStyle(PicoSecondaryButtonStyle())
            .disabled(focusStore.hasPendingResultSync)
            .opacity(focusStore.hasPendingResultSync ? 0.62 : 1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MultiplayerInviteFriendsSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    @Binding var step: StartFocusSheetStep
    @Binding var durationSeconds: Int
    let buttonTitle: String
    @State private var searchText = ""
    @State private var selectedFriendIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            UserProfileSearchList(
                searchText: $searchText,
                placeholder: "Search friends",
                isLoading: friendStore.isLoadingFriends,
                loadingText: "Loading friends",
                emptyText: searchText.isEmpty ? "No friends available to invite." : "No friends match that search.",
                profiles: availableFriends
            ) { friend in
                FriendInviteSelectionRow(
                    friend: friend,
                    isSelected: selectedFriendIDs.contains(friend.userID)
                ) {
                    toggle(friend)
                }
            }

            if shouldShowGroupLimitNotice {
                PicoPlusGroupLimitNotice(
                    notice: picoPlusStore.notice,
                    source: largeGroupPaywallSource
                )
            }

            Button {
                Task {
                    await sendInvites()
                }
            } label: {
                FocusSheetActionLabel(
                    title: buttonTitle,
                    imageName: "Envolope",
                    imageFrameSize: CGSize(width: 27, height: 18),
                    placement: .trailing,
                    showsProgress: isBusy,
                    progressTint: PicoColors.textPrimary
                )
            }
            .buttonStyle(PicoSecondaryButtonStyle())
            .disabled(selectedFriendIDs.isEmpty || isBusy || focusStore.hasPendingResultSync)
            .opacity(selectedFriendIDs.isEmpty || isBusy || focusStore.hasPendingResultSync ? 0.62 : 1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await friendStore.loadFriends(for: sessionStore.session)
        }
    }

    private var isBusy: Bool {
        focusStore.isCreating || focusStore.isInvitingMembers || focusStore.isUpdatingConfig
    }

    private var unavailableMemberIDs: Set<UUID> {
        Set(
            focusStore.sessionDetail?.members
                .filter { $0.status == .joined || $0.status == .invited }
                .map(\.userID) ?? []
        )
    }

    private var currentMemberCount: Int {
        if let members = focusStore.sessionDetail?.members {
            return members.filter { $0.status == .joined || $0.status == .invited }.count
        }

        return 1
    }

    private var remainingInviteSlots: Int {
        picoPlusStore.capabilities.remainingMultiplayerInviteSlots(currentMemberCount: currentMemberCount)
    }

    private var shouldShowGroupLimitNotice: Bool {
        picoPlusStore.capabilities.selectedInvitesReachMultiplayerLimit(
            currentMemberCount: currentMemberCount,
            selectedInviteCount: selectedFriendIDs.count
        )
    }

    private var largeGroupPaywallSource: PicoPlusPaywallSource {
        .largeGroupSession(
            currentMembers: currentMemberCount,
            selectedInvites: selectedFriendIDs.count,
            limit: picoPlusStore.capabilities.freeMultiplayerMemberLimit,
            placement: .largeGroupSession
        )
    }

    private var availableFriends: [UserProfile] {
        let filtered = friendStore.friends.filter { !unavailableMemberIDs.contains($0.userID) }
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func toggle(_ friend: UserProfile) {
        if selectedFriendIDs.contains(friend.userID) {
            selectedFriendIDs.remove(friend.userID)
        } else {
            guard selectedFriendIDs.count < remainingInviteSlots else {
                return
            }

            selectedFriendIDs.insert(friend.userID)
        }
    }

    private func sendInvites() async {
        let selectedFriends = friendStore.friends.filter { selectedFriendIDs.contains($0.userID) }
        guard !selectedFriends.isEmpty else { return }
        guard selectedFriends.count <= remainingInviteSlots else {
            return
        }

        if focusStore.lobbySession?.mode != .multiplayer {
            await focusStore.createLobby(
                mode: .multiplayer,
                durationSeconds: durationSeconds,
                for: sessionStore.session
            )
        } else if focusStore.lobbySession?.durationSeconds != durationSeconds {
            await focusStore.updateLobbyDuration(durationSeconds, for: sessionStore.session)
        }

        guard focusStore.lobbySession?.mode == .multiplayer else { return }

        await focusStore.inviteFriends(selectedFriends, for: sessionStore.session)
        selectedFriendIDs = []
        step = .multiplayerLobby
    }

}

private struct FriendInviteSelectionRow: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let friend: UserProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(
                    config: friend.avatarConfig,
                    size: 40,
                    scarf: scarf(for: friend.userID)
                )

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(friend.displayName)
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)

                    Text("@\(friend.username)")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(PicoTypography.symbol(size: 23, weight: .semibold))
                    .foregroundStyle(isSelected ? PicoColors.primary : PicoColors.textMuted)
            }
            .contentShape(Rectangle())
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.sheetCardPadding,
                background: isSelected ? PicoCreamCardStyle.controlBackground : PicoCreamCardStyle.background,
                border: isSelected ? PicoColors.primary : PicoCreamCardStyle.border
            )
        }
        .buttonStyle(.plain)
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func scarf(for userID: UUID) -> AvatarScarf? {
        villageStore.scarf(
            for: userID,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }

}

private struct PicoPlusGroupLimitNotice: View {
    let notice: String?
    let source: PicoPlusPaywallSource

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            Text("Your session is full")
                .font(PicoTypography.body.weight(.bold))
                .foregroundStyle(PicoColors.textPrimary)

            Text("Invite more friends with plus")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let notice {
                Text(notice)
                    .font(PicoTypography.caption.weight(.semibold))
                    .foregroundStyle(PicoColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PicoPlusCTAButton(title: "Unlock bigger groups", source: source)
                .accessibilityHint(Text("Pico Plus unlocks larger group sessions."))
        }
        .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
    }
}

private struct MultiplayerLobbySheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore

    @Binding var step: StartFocusSheetStep
    @Binding var isPresented: Bool
    let session: FocusSession?

	    var body: some View {
	        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
	            if let session {
                FocusDurationBadge(
                    seconds: session.durationSeconds,
                    imageName: "Anchor",
                    imageFrameSize: CGSize(width: 13, height: 20)
                )
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: PicoSpacing.iconTextGap) {
                    Text("Session members")
                        .font(PicoTypography.body.weight(.bold))
                        .foregroundStyle(PicoColors.textPrimary)

                    Spacer()

                    if focusStore.isCurrentUserHost(sessionStore.session) {
                        Button {
                            step = .multiplayerInviteMore
                        } label: {
                            HStack(spacing: PicoSpacing.compact) {
                                SheetActionImageIcon(
                                    imageName: "Envolope",
                                    frameSize: CGSize(width: 19, height: 12)
                                )
                                Text("Invite")
                            }
                                .font(PicoTypography.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PicoColors.primary)
                        .disabled(focusStore.isInvitingMembers || focusStore.isStarting || focusStore.isFinishing)
                    }
                }

                ScrollView {
                    VStack(spacing: PicoSpacing.compact) {
                        if let detail = focusStore.sessionDetail {
                            ForEach(homeSortedMembers(detail.members)) { member in
                                FocusMemberStatusRow(member: member)
                            }
                        } else {
                            HStack {
                                Text("Loading members")
                                    .font(PicoTypography.caption)
                                    .foregroundStyle(PicoColors.textSecondary)
                                Spacer()
                                ProgressView()
                                    .tint(PicoColors.primary)
                            }
                            .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
	                .layoutPriority(1)

	                if focusStore.isCurrentUserHost(sessionStore.session) {
	                    if let readinessText {
	                        Text(readinessText)
	                            .font(PicoTypography.caption.weight(.semibold))
	                            .foregroundStyle(PicoColors.textSecondary)
	                            .frame(maxWidth: .infinity, alignment: .center)
	                    }
	
                    Button {
                        Task {
                            await focusStore.startLobbySession(for: sessionStore.session)
                        }
                    } label: {
                        HStack {
                            Text("Start")
                            FishingPoleCTAIcon()
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)

                            if focusStore.isStarting {
                                ProgressView()
                                    .tint(PicoColors.textOnPrimary)
                            }
                        }
                    }
                    .buttonStyle(PicoPrimaryButtonStyle())
                    .disabled(!canStartSession || focusStore.isStarting || focusStore.isFinishing)
                    .opacity(!canStartSession || focusStore.isStarting || focusStore.isFinishing ? 0.62 : 1)

                    Button {
                        Task {
                            let didCancel = await focusStore.cancelLobbySession(for: sessionStore.session)
                            if didCancel {
                                step = .modePicker
                                isPresented = false
                            }
                        }
                    } label: {
                        Text("Cancel lobby")
                            .font(PicoTypography.caption.weight(.semibold))
                            .foregroundStyle(PicoColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -PicoSpacing.tiny)
                    .disabled(focusStore.isFinishing)
                } else {
                    Text("Waiting for host to start")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button(role: .destructive) {
                        Task {
                            await focusStore.leaveCurrentMultiplayerSession(for: sessionStore.session)
                        }
                    } label: {
                        Text("Leave Lobby")
                            .font(PicoTypography.caption.weight(.semibold))
                            .foregroundStyle(PicoColors.error)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -PicoSpacing.tiny)
                    .disabled(focusStore.isFinishing)
                }
            } else {
                ProgressView("Creating lobby")
                    .tint(PicoColors.primary)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
            }
	        }
		        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		    }
	
	    private var readinessText: String? {
	        guard let members = focusStore.sessionDetail?.members else { return nil }
	        let joinedNonHostCount = members.filter { $0.role != .host && $0.status == .joined }.count
	        if joinedNonHostCount == 0 {
	            if members.contains(where: { $0.status == .invited }) {
	                return "Waiting for members to join"
	            }
	            return "Invite members to start session"
	        }

	        let readyCount = members.filter { $0.status == .joined }.count
	        return "\(readyCount) of \(members.count) ready"
	    }

	    private var canStartSession: Bool {
	        focusStore.sessionDetail?.members.contains {
	            $0.role != .host && $0.status == .joined
	        } == true
    }
}

private struct ActiveSessionTimerBottomBar: View {
    let session: FocusSession

    var body: some View {
        ActiveSessionTimerStrip(session: session)
            .padding(.horizontal, 44)
            .padding(.top, PicoSpacing.compact)
            .padding(.bottom, PicoSpacing.compact)
            .background(
                PicoColors.appBackground
                    .opacity(0.96)
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

private struct ActiveSessionTimerStrip: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var villageStore: VillageStore
    @State private var now = Date()

    let session: FocusSession
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            Text(homeFormattedDuration(session.remainingSeconds(at: now)))
                .font(PicoTypography.largeValue)
                .monospacedDigit()
                .foregroundStyle(PicoColors.textPrimary)

            Button {
                Task {
                    if canLeaveMultiplayer {
                        await focusStore.leaveCurrentMultiplayerSession(for: sessionStore.session)
                    } else {
                        await focusStore.interruptCurrentSession(for: sessionStore.session)
                    }
                }
            } label: {
                Text(canLeaveMultiplayer ? "leave" : "cancel")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textMuted)
                    .padding(.horizontal, PicoSpacing.compact)
                    .padding(.vertical, PicoSpacing.tiny)
            }
            .buttonStyle(.plain)
            .disabled(focusStore.isFinishing)
            .opacity(focusStore.isFinishing ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { date in
            now = date
            guard session.remainingSeconds(at: date) == 0, !focusStore.isFinishing else { return }
            Task {
                await focusStore.completeCurrentSession(
                    for: sessionStore.session,
                    preCompletionVillageResidentIDs: currentVillageResidentIDs
                )
            }
        }
    }

    private var canLeaveMultiplayer: Bool {
        session.mode == .multiplayer
    }

    private var currentVillageResidentIDs: Set<UUID> {
        Set(villageStore.residents.map(\.profile.userID))
    }
}

private struct FocusCompleteOverlay: View {
    let session: FocusSession
    let completionContext: FocusCompletionContext?
    let failureContext: FocusFailureContext?
    let done: () -> Void

    var body: some View {
        ZStack {
            PicoColors.appBackground
                .ignoresSafeArea()

            FocusCompleteCard(
                session: session,
                completionContext: completionContext,
                failureContext: failureContext,
                done: done
            )
                .padding(.horizontal, PicoSpacing.standard)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FocusCompleteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var berryStore: BerryStore
    @EnvironmentObject private var focusStore: FocusStore

    let session: FocusSession
    let completionContext: FocusCompletionContext?
    let failureContext: FocusFailureContext?
    let done: () -> Void

    private var avatarConfig: AvatarConfig {
        sessionStore.profile?.avatarConfig ?? AvatarCatalog.defaultConfig
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(resultTitle)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

            if let resultSubtitle {
                Text(resultSubtitle)
                    .font(PicoTypography.bodySemibold)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, PicoSpacing.tiny)
            }

            if let groupTogetherText {
                Text(groupTogetherText)
                    .font(PicoTypography.caption.weight(.bold))
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .padding(.top, PicoSpacing.tiny)
            }

            celebrationContent

            if session.status != .completed && session.status != .failed {
                rewardContent
                    .padding(.top, PicoSpacing.standard)
            }

            if focusStore.hasPendingResultSync {
                Button {
                    Task {
                        await focusStore.retryPendingResult(for: sessionStore.session)
                    }
                } label: {
                    HStack {
                        Text("Retry Saving Result")
                        if focusStore.isFinishing {
                            ProgressView()
                                .tint(PicoColors.textOnPrimary)
                        }
                    }
                }
                .buttonStyle(PicoPrimaryButtonStyle())
                .disabled(focusStore.isFinishing)
                .padding(.top, PicoSpacing.standard)

                if let notice = focusStore.notice {
                    Text(notice)
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, PicoSpacing.tiny)
                }
            } else {
                Button(doneButtonTitle) {
                    done()
                }
                .buttonStyle(PicoPrimaryButtonStyle())
                .padding(.top, PicoSpacing.standard)
            }
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.top, PicoSpacing.section)
        .padding(.bottom, PicoSpacing.compact)
        .picoCreamCard()
    }

    private var resultTitle: String {
        switch session.status {
        case .completed:
            return "Focus Complete!"
        case .failed:
            return failedResultTitle
        case .cancelled:
            return "Session Cancelled"
        case .lobby, .active:
            return "Session"
        }
    }

    private var resultSubtitle: String? {
        guard session.status == .failed else { return nil }
        return session.mode == .multiplayer ? nil : "The catch swam away"
    }

    private var failedResultTitle: String {
        guard session.mode == .multiplayer else { return "Catch got away" }
        guard let failureContext else { return "Someone broke focus" }

        if failureContext.isMemberLeaveFailure {
            if failureContext.isCurrentUserFailure {
                return "You left the session"
            }

            if let name = failureContext.failedMemberDisplayName {
                return "\(name) left the session"
            }

            return "Someone left the session"
        }

        if failureContext.isCurrentUserFailure {
            return "You broke focus"
        }

        if let name = failureContext.failedMemberDisplayName {
            return "\(name) broke focus"
        }

        return "Someone broke focus"
    }

    private var doneButtonTitle: String {
        session.status == .failed ? "Try again" : "Done"
    }

    private var scoreLabel: String {
        session.status == .completed ? "Fish caught" : formattedBerryCount(0)
    }

    private var streakLabel: String {
        let streak = berryStore.completionStreak
        return "\(streak) day\(streak == 1 ? "" : "s") streak"
    }

    private var groupCompletionContext: FocusCompletionContext? {
        guard session.status == .completed else { return nil }
        return completionContext
    }

    private var failedLeaveMember: FocusSessionMember? {
        guard session.status == .failed,
              failureContext?.isMemberLeaveFailure == true,
              failureContext?.isCurrentUserFailure == false else {
            return nil
        }

        return failureContext?.failedMember
    }

    private var groupTogetherText: String? {
        guard let groupCompletionContext else { return nil }
        let peerNames = groupCompletionContext.peerMembers.map(\.profile.displayName)

        switch peerNames.count {
        case 0:
            return nil
        case 1:
            return "Together with \(peerNames[0])"
        case 2:
            return "Together with \(peerNames[0]) and \(peerNames[1])"
        default:
            return "Together with \(peerNames.count) others"
        }
    }

    private var showsConfetti: Bool {
        session.status == .completed
    }

    @ViewBuilder
    private var celebrationContent: some View {
        if let failedLeaveMember {
            FocusFailedMemberAvatar(member: failedLeaveMember)
                .padding(.top, PicoSpacing.tiny)
        } else if session.status == .failed {
            FocusInterruptedEmptyBucketImage()
                .padding(.top, PicoSpacing.standard)
        } else if let groupCompletionContext {
            FocusCompleteGroupCelebrationView(
                context: groupCompletionContext,
                reduceMotion: reduceMotion,
                showsConfetti: showsConfetti
            )
        } else {
            ZStack {
                if showsConfetti {
                    FocusCompleteConfettiView(reduceMotion: reduceMotion)
                        .frame(width: 260, height: FocusCompleteAvatarLayout.celebrationHeight)
                        .allowsHitTesting(false)
                }

                UserAvatar(
                    config: avatarConfig,
                    maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
                    usesHappyIdle: true
                )
                .frame(
                    width: FocusCompleteAvatarLayout.avatarWidth,
                    height: FocusCompleteAvatarLayout.avatarHeight
                )
            }
            .frame(height: FocusCompleteAvatarLayout.celebrationHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private var rewardContent: some View {
        if let groupCompletionContext {
            FocusCompleteRewardGrid(
                metrics: groupMetrics(for: groupCompletionContext)
            )
        } else {
            HStack(alignment: .center) {
                FocusCompleteMetric(
                    title: scoreLabel,
                    icon: .sparklesSolid,
                    iconColor: PicoColors.primary
                )

                Spacer()

                FocusCompleteMetric(
                    title: streakLabel,
                    icon: .fireSolid,
                    iconColor: PicoColors.streakAccent
                )
            }
            .padding(.vertical, PicoSpacing.tiny)
        }
    }

    private func groupMetrics(for _: FocusCompletionContext) -> [FocusCompleteMetricModel] {
        []
    }
}

private struct FocusFailedMemberAvatar: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let member: FocusSessionMember

    var body: some View {
        UserAvatar(
            config: member.profile.avatarConfig,
            maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
            usesHappyIdle: false,
            scarf: scarf(for: member.userID)
        )
        .frame(
            width: FocusCompleteAvatarLayout.avatarWidth,
            height: FocusCompleteAvatarLayout.avatarHeight
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(member.profile.displayName))
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func scarf(for userID: UUID) -> AvatarScarf? {
        villageStore.scarf(
            for: userID,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }
}

private struct FocusInterruptedEmptyBucketImage: View {
    var body: some View {
        if let image = UIImage(named: "Icons/Empty_Bucket") ?? UIImage(named: "Icons/Empty_Bucket.png") ?? UIImage(named: "Empty_Bucket") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 62)
                .accessibilityHidden(true)
        }
    }
}

private enum FocusCompleteAvatarLayout {
    static let spriteSide: CGFloat = 116
    static let avatarWidth: CGFloat = 132
    static let avatarHeight: CGFloat = 118
    static let celebrationHeight: CGFloat = 118
    static let namedCelebrationHeight: CGFloat = 150
    static let memberNameWidth: CGFloat = 124
}

private struct FocusCompleteGroupCelebrationView: View {
    let context: FocusCompletionContext
    let reduceMotion: Bool
    let showsConfetti: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsConfetti {
                    FocusCompleteConfettiView(reduceMotion: reduceMotion)
                        .frame(width: 280, height: FocusCompleteAvatarLayout.celebrationHeight)
                        .allowsHitTesting(false)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: PicoSpacing.compact) {
                        ForEach(context.members) { member in
                            FocusCompleteGroupMemberPill(
                                member: member,
                                isNewPeer: context.isNewPeer(member)
                            )
                        }
                    }
                    .padding(.horizontal, PicoSpacing.compact)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .frame(height: FocusCompleteAvatarLayout.namedCelebrationHeight)
            }
            .frame(height: FocusCompleteAvatarLayout.namedCelebrationHeight)
            .clipped()
        }
    }
}

private struct FocusCompleteGroupMemberPill: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let member: FocusSessionMember
    let isNewPeer: Bool

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            ZStack(alignment: .topTrailing) {
                UserAvatar(
                    config: member.profile.avatarConfig,
                    maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
                    usesHappyIdle: true,
                    scarf: scarf(for: member.userID)
                )
                .frame(
                    width: FocusCompleteAvatarLayout.avatarWidth,
                    height: FocusCompleteAvatarLayout.avatarHeight
                )

                if isNewPeer {
                    Text("New")
                        .font(PicoTypography.tinyCaptionBold)
                        .foregroundStyle(PicoColors.textOnPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(PicoColors.primary)
                        .clipShape(Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PicoCreamCardStyle.background, lineWidth: 2)
                        )
                        .accessibilityLabel(Text("New"))
                }
            }

            Text(member.profile.displayName)
                .font(PicoTypography.caption.weight(.semibold))
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: FocusCompleteAvatarLayout.memberNameWidth)
        }
        .frame(width: FocusCompleteAvatarLayout.avatarWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isNewPeer ? "\(member.profile.displayName), new" : member.profile.displayName))
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func scarf(for userID: UUID) -> AvatarScarf? {
        villageStore.scarf(
            for: userID,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }
}

private struct FocusCompleteMetricModel: Identifiable {
    let id = UUID()
    let title: String
    let icon: PicoIconAsset
    let iconColor: Color
}

private struct FocusCompleteRewardGrid: View {
    let metrics: [FocusCompleteMetricModel]

    private let columns = [
        GridItem(.flexible(), spacing: PicoSpacing.standard),
        GridItem(.flexible(), spacing: PicoSpacing.standard)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: PicoSpacing.standard) {
            ForEach(metrics) { metric in
                FocusCompleteMetric(
                    title: metric.title,
                    icon: metric.icon,
                    iconColor: metric.iconColor
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, PicoSpacing.tiny)
    }
}

private struct FocusCompleteConfettiView: View {
    let reduceMotion: Bool
    @State private var startDate = Date()

    private let burstDuration: TimeInterval = 1.9
    private let cycleDuration: TimeInterval = 3.2
    private let particles = FocusCompleteConfettiParticle.particles

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(startDate)
                let cycleElapsed = reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: cycleDuration)

                for particle in particles {
                    let progress = reduceMotion ? 0.34 : particle.progress(at: cycleElapsed)
                    guard progress > 0 || reduceMotion else { continue }

                    let easedProgress = 1 - pow(1 - progress, 2)
                    let x = size.width * particle.unitX + particle.drift * CGFloat(easedProgress)
                    let y = size.height * particle.startY + particle.fall * CGFloat(easedProgress)
                    let opacity = reduceMotion ? 0.72 : particle.opacity(at: progress)
                    guard opacity > 0 else { continue }

                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(particle.rotation(at: progress)))
                        layer.fill(
                            particle.path,
                            with: .color(particle.color.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear {
            startDate = Date()
        }
        .accessibilityHidden(true)
    }
}

private struct FocusCompleteConfettiParticle {
    enum Shape {
        case circle
        case roundedRect
    }

    let unitX: CGFloat
    let startY: CGFloat
    let drift: CGFloat
    let fall: CGFloat
    let delay: TimeInterval
    let duration: TimeInterval
    let size: CGSize
    let shape: Shape
    let color: Color
    let spin: Double

    var path: Path {
        let rect = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )

        switch shape {
        case .circle:
            return Path(ellipseIn: rect)
        case .roundedRect:
            return Path(roundedRect: rect, cornerRadius: min(size.width, size.height) * 0.28)
        }
    }

    func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= delay else { return 0 }
        return min(1, max(0, (elapsed - delay) / duration))
    }

    func opacity(at progress: Double) -> Double {
        min(1, max(0, 1 - pow(progress, 2.4)))
    }

    func rotation(at progress: Double) -> Double {
        spin * progress
    }

    static let particles: [FocusCompleteConfettiParticle] = [
        .init(unitX: 0.16, startY: 0.18, drift: -8, fall: 58, delay: 0.00, duration: 1.55, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.warning, spin: 2.4),
        .init(unitX: 0.24, startY: 0.08, drift: 14, fall: 72, delay: 0.03, duration: 1.68, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.streakAccent, spin: -2.1),
        .init(unitX: 0.35, startY: 0.12, drift: -12, fall: 66, delay: 0.08, duration: 1.52, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.primary, spin: 1.7),
        .init(unitX: 0.63, startY: 0.10, drift: 10, fall: 74, delay: 0.02, duration: 1.62, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.error, spin: 2.9),
        .init(unitX: 0.74, startY: 0.16, drift: -11, fall: 56, delay: 0.11, duration: 1.46, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.warning, spin: -2.7),
        .init(unitX: 0.86, startY: 0.20, drift: 9, fall: 62, delay: 0.05, duration: 1.58, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.primary, spin: 2.2),
        .init(unitX: 0.20, startY: 0.42, drift: 18, fall: 42, delay: 0.18, duration: 1.38, size: CGSize(width: 4, height: 4), shape: .circle, color: PicoColors.secondaryAccent, spin: -1.5),
        .init(unitX: 0.30, startY: 0.36, drift: -13, fall: 48, delay: 0.13, duration: 1.44, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.primary, spin: 2.1),
        .init(unitX: 0.44, startY: 0.30, drift: 15, fall: 54, delay: 0.21, duration: 1.36, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.warning, spin: -2.8),
        .init(unitX: 0.57, startY: 0.32, drift: -15, fall: 52, delay: 0.16, duration: 1.42, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.error, spin: 2.5),
        .init(unitX: 0.70, startY: 0.40, drift: 12, fall: 46, delay: 0.12, duration: 1.50, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.streakAccent, spin: -1.9),
        .init(unitX: 0.82, startY: 0.38, drift: -18, fall: 44, delay: 0.22, duration: 1.32, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.secondaryAccent, spin: 2.4),
        .init(unitX: 0.12, startY: 0.60, drift: 13, fall: 28, delay: 0.28, duration: 1.18, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.primary, spin: -2.3),
        .init(unitX: 0.26, startY: 0.62, drift: -16, fall: 34, delay: 0.24, duration: 1.24, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.warning, spin: 1.8),
        .init(unitX: 0.38, startY: 0.58, drift: 10, fall: 38, delay: 0.30, duration: 1.20, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.error, spin: 2.6),
        .init(unitX: 0.62, startY: 0.58, drift: -10, fall: 38, delay: 0.27, duration: 1.22, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.primary, spin: -2.5),
        .init(unitX: 0.75, startY: 0.64, drift: 16, fall: 32, delay: 0.25, duration: 1.26, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.streakAccent, spin: 2.1),
        .init(unitX: 0.88, startY: 0.60, drift: -12, fall: 30, delay: 0.31, duration: 1.14, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.warning, spin: -1.6),
        .init(unitX: 0.18, startY: 0.76, drift: -9, fall: 20, delay: 0.38, duration: 1.02, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.secondaryAccent, spin: 2.0),
        .init(unitX: 0.34, startY: 0.74, drift: 11, fall: 24, delay: 0.34, duration: 1.10, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.primary, spin: -1.4),
        .init(unitX: 0.51, startY: 0.78, drift: -7, fall: 22, delay: 0.40, duration: 1.00, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.error, spin: 2.5),
        .init(unitX: 0.66, startY: 0.76, drift: 9, fall: 24, delay: 0.36, duration: 1.06, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.warning, spin: -2.4),
        .init(unitX: 0.80, startY: 0.78, drift: -10, fall: 20, delay: 0.42, duration: 0.96, size: CGSize(width: 4, height: 4), shape: .circle, color: PicoColors.primary, spin: 1.5),
        .init(unitX: 0.47, startY: 0.08, drift: 7, fall: 78, delay: 0.06, duration: 1.72, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.secondaryAccent, spin: -3.0)
    ]
}

private struct FocusCompleteMetric: View {
    let title: String
    let icon: PicoIconAsset
    let iconColor: Color

    var body: some View {
        Label {
            Text(title)
                .font(PicoTypography.caption.weight(.bold))
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        } icon: {
            PicoIcon(icon, size: 14)
                .foregroundStyle(iconColor)
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct FocusMemberStatusRow: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let member: FocusSessionMember

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            AvatarBadgeView(
                config: member.profile.avatarConfig,
                size: 40,
                scarf: scarf(for: member.userID)
            )

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                HStack(spacing: PicoSpacing.tiny) {
                    Text(member.profile.displayName)
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)

                    if member.role == .host {
                        Image(systemName: "crown.fill")
                            .font(PicoTypography.symbol(size: 11, weight: .medium))
                            .foregroundStyle(PicoColors.warning)
                    }
                }

                Text("@\(member.profile.username)")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
            }

            Spacer(minLength: 0)

            Text(homeMemberStatusText(member))
                .font(PicoTypography.caption.weight(.semibold))
                .foregroundStyle(homeMemberStatusColor(member))
        }
        .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
    }

    private var currentUserID: UUID? {
        sessionStore.session?.user?.id ?? sessionStore.profile?.userID
    }

    private func scarf(for userID: UUID) -> AvatarScarf? {
        villageStore.scarf(
            for: userID,
            ownerID: currentUserID,
            bondRewardClaimStore: bondRewardClaimStore,
            capabilities: picoPlusStore.capabilities
        )
    }
}

private func homeSortedMembers(_ members: [FocusSessionMember]) -> [FocusSessionMember] {
    members.sorted {
        if $0.role != $1.role {
            return $0.role == .host
        }
        return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
    }
}

private func homeMemberStatusText(_ member: FocusSessionMember) -> String {
    if member.isInterrupted {
        return "Interrupted"
    }

    if member.isCompleted {
        return "Complete"
    }

    switch member.status {
    case .invited:
        return "invited"
    case .joined:
        return "ready"
    case .left:
        return "left"
    }
}

private func homeMemberStatusColor(_ member: FocusSessionMember) -> Color {
    if member.isInterrupted || member.status == .left {
        return PicoColors.textSecondary
    }

	    if member.isCompleted || member.status == .joined {
	        return PicoColors.primary
	    }

    return PicoColors.textSecondary
}

private func homeFormattedDuration(_ seconds: Int) -> String {
    let clampedSeconds = max(0, seconds)
    let minutes = clampedSeconds / 60
    let seconds = clampedSeconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
}

private func homeFormattedDurationMinutes(_ seconds: Int) -> String {
    let clampedSeconds = max(0, seconds)
    if clampedSeconds < 60 {
        return "\(clampedSeconds) sec"
    }

    let minutes = Int(ceil(Double(clampedSeconds) / 60))
    return "\(minutes) min"
}

private func clampedDurationSeconds(from seconds: Int) -> Int {
    min(FocusStore.maximumDurationSeconds, max(FocusStore.minimumDurationSeconds, seconds))
}

func formattedBerryCount(_ count: Int) -> String {
    "\(count) \(count == 1 ? "berry" : "berries")"
}

private struct BerryAmountLabel: View {
    let count: Int
    var font: Font
    var iconSize: CGFloat
    var textColor: Color = PicoColors.textPrimary

    var body: some View {
        HStack(spacing: PicoSpacing.tiny) {
            BerryBalanceIcon(size: iconSize)

            Text("\(count)")
                .font(font)
                .foregroundStyle(textColor)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(formattedBerryCount(count)))
    }
}

private struct FishingPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var fishStore: FishStore
    @EnvironmentObject private var islandStore: IslandStore
    let openStore: () -> Void
    @State private var selectedMode: FishingPageMode = .collection
    @State private var selectedCollectionIsland: PicoIsland = .original

    private var catalogFish: [FishingCatalogFish] {
        guard fishStore.fishCatalogIslandID == selectedCollectionIslandID else { return [] }

        return fishStore.fishCatalog
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap(FishingCatalogFish.init(catalogItem:))
    }

    private var collectionCounts: [FishID: Int] {
        guard fishStore.collectionCountsIslandID == selectedCollectionIslandID else { return [:] }

        return Dictionary(
            uniqueKeysWithValues: fishStore.collectionCounts.map { count in
                (count.seaCritterID, count.count)
            }
        )
    }

    private var collectionDiscoveryText: String {
        let discoveredCount = catalogFish.filter { fish in
            collectionCounts[fish.seaCritterID, default: 0] > 0
        }.count

        return "\(discoveredCount)/\(catalogFish.count) discovered"
    }

    private var islandDiscoverySummaries: [String: FishingIslandDiscoverySummary] {
        Dictionary(
            uniqueKeysWithValues: PicoIsland.allCases.map { island in
                (
                    island.backendID,
                    FishingIslandDiscoverySummary(counts: fishStore.islandCollectionCounts[island.backendID])
                )
            }
        )
    }

    private var inventoryGroups: [StoreFishGroup] {
        StoreFishGroup.groups(
            from: fishStore.inventory,
            catalog: fishStore.fishCatalogIslandID == islandStore.selectedIslandID ? fishStore.fishCatalog : [],
            inventoryCounts: fishStore.inventoryCounts
        )
    }

    private var taskID: String {
        switch selectedMode {
        case .collection:
            "\(selectedMode.rawValue)-\(selectedCollectionIsland.rawValue)"
        case .inventory, .islands:
            "\(selectedMode.rawValue)-\(islandStore.selectedIsland.rawValue)"
        }
    }

    private var selectedCollectionIslandID: String {
        selectedCollectionIsland.backendID
    }

    private var selectedCollectionIslandIsOwned: Bool {
        selectedCollectionIsland == .original
            || sessionStore.ownedIslandIDs.contains(selectedCollectionIsland.backendID)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PicoSpacing.section) {
                if let notice = fishStore.notice {
                    ProfileNoticeCard(text: notice)
                }

                Picker("Fishing view", selection: $selectedMode) {
                    ForEach(FishingPageMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedMode {
                case .collection:
                    VStack(alignment: .leading, spacing: 0) {
                        FishingCollectionHeader(
                            selectedIsland: $selectedCollectionIsland,
                            discoveryText: collectionDiscoveryText,
                            isLocked: !selectedCollectionIslandIsOwned
                        )

                        if !selectedCollectionIslandIsOwned {
                            FishingCollectionBuyIslandCTA(
                                island: selectedCollectionIsland,
                                openStore: openStore
                            )
                            .padding(.top, PicoSpacing.compact)
                        }

                        FishingCollectionSections(
                            catalogFish: catalogFish,
                            counts: collectionCounts
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .inventory:
                    FishingInventorySection(
                        groups: inventoryGroups,
                        isLoading: fishStore.isLoadingInventory || fishStore.isLoadingInventoryCounts
                    )
                case .islands:
                    FishingIslandSelectionSection(
                        selectedIsland: islandStore.selectedIsland,
                        isSessionLocked: focusStore.isIslandSelectionLocked,
                        ownedIslandIDs: sessionStore.ownedIslandIDs,
                        isLoading: fishStore.isLoadingIslandCollectionCounts,
                        summaries: islandDiscoverySummaries,
                        openStore: openStore,
                        selectIsland: selectIsland
                    )
                }
            }
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.vertical, PicoSpacing.section)
            .padding(.bottom, PicoSpacing.largeSection)
        }
        .picoScreenBackground()
        .task(id: taskID) {
            await loadSelectedFishingData(forceReloadCounts: selectedMode == .collection)
        }
        .refreshable {
            await loadSelectedFishingData(forceReload: true)
        }
    }

    private func loadSelectedFishingData(
        forceReload: Bool = false,
        forceReloadCounts: Bool = false
    ) async {
        switch selectedMode {
        case .collection:
            await loadCollectionData(
                forceReload: forceReload,
                forceReloadCounts: forceReloadCounts
            )
        case .inventory:
            await loadInventoryData(forceReload: forceReload)
        case .islands:
            await fishStore.loadIslandCollectionCounts(
                for: sessionStore.session,
                islandIDs: PicoIsland.allCases.map(\.backendID),
                forceReload: forceReload
            )
        }
    }

    private func loadCollectionData(
        forceReload: Bool = false,
        forceReloadCounts: Bool = false
    ) async {
        if forceReload || fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != selectedCollectionIslandID {
            await fishStore.loadFishCatalog(
                for: sessionStore.session,
                islandID: selectedCollectionIslandID,
                forceReload: forceReload
            )
        }

        await fishStore.loadCollectionCounts(
            for: sessionStore.session,
            islandID: selectedCollectionIslandID,
            forceReload: forceReload || forceReloadCounts
        )
    }

    private func loadInventoryData(forceReload: Bool = false) async {
        if forceReload || fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
            await fishStore.loadFishCatalog(
                for: sessionStore.session,
                islandID: islandStore.selectedIslandID,
                forceReload: forceReload
            )
        }

        await fishStore.loadInventoryCounts(for: sessionStore.session)
        await fishStore.loadInventory(for: sessionStore.session)
    }

    private func selectIsland(_ island: PicoIsland) {
        guard !focusStore.isIslandSelectionLocked else { return }
        guard islandStore.isOwned(island) else { return }

        withAnimation(.snappy(duration: 0.22)) {
            islandStore.select(island)
        }
    }
}

private struct FishingCollectionBuyIslandCTA: View {
    let island: PicoIsland
    let openStore: () -> Void

    var body: some View {
        Button(action: openStore) {
            Text("Buy in store")
                .font(PicoTypography.statusLabel)
                .foregroundStyle(PicoColors.textOnPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PicoColors.primary)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text("Buy \(island.collectionDisplayName) in store"))
    }
}

private enum FishingPageMode: String, CaseIterable, Identifiable {
    case collection
    case inventory
    case islands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection:
            "Collection"
        case .inventory:
            "Inventory"
        case .islands:
            "Islands"
        }
    }
}

private struct FishingCollectionHeader: View {
    @Binding var selectedIsland: PicoIsland
    let discoveryText: String
    let isLocked: Bool

    var body: some View {
        HStack(alignment: .center, spacing: PicoSpacing.iconTextGap) {
            Menu {
                ForEach(PicoIsland.allCases) { island in
                    Button {
                        selectedIsland = island
                    } label: {
                        Label {
                            Text(island.collectionDisplayName)
                        } icon: {
                            FishingCollectionIslandMenuIcon(island: island)
                        }
                    }
                }
            } label: {
                HStack(spacing: PicoSpacing.compact) {
                    FishingIslandSelectorIcon(island: selectedIsland)
                        .frame(width: 24, height: 24)

                    Text(selectedIsland.collectionDisplayName)
                        .font(PicoTypography.cardTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Image(systemName: "chevron.down")
                        .font(PicoTypography.symbol(size: 13, weight: .bold))
                        .foregroundStyle(PicoColors.textPrimary)
                        .accessibilityHidden(true)
                }
                .contentShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text("Collection island, \(selectedIsland.collectionDisplayName)"))

            HStack(spacing: PicoSpacing.tiny) {
                if isLocked {
                    PicoIcon(.lockClosed, size: 11)
                        .foregroundStyle(PicoColors.textSecondary)
                        .accessibilityHidden(true)
                }

                Text(discoveryText)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
            }
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isLocked ? "Locked, \(discoveryText)" : discoveryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FishingCollectionIslandMenuIcon: View {
    let island: PicoIsland

    var body: some View {
        FishingIslandSelectorIcon(island: island)
            .frame(width: 22, height: 22)
        .frame(width: 24, height: 24)
    }
}

private struct FishingInventorySection: View {
    let groups: [StoreFishGroup]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                FishingCountIcon(name: "Bucket")
                    .frame(width: 24, height: 24)

                Text("Inventory")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                }
            }

            if groups.isEmpty && !isLoading {
                Text("No fish in inventory.")
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PicoSpacing.tiny)
            } else {
                VStack(spacing: PicoSpacing.compact) {
                    ForEach(groups) { group in
                        FishingInventoryRow(group: group)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FishingInventoryRow: View {
    let group: StoreFishGroup

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            fishIcon

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text(group.displayName)
                    .font(PicoTypography.fishName)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)

                rarityTag
            }

            Spacer(minLength: PicoSpacing.compact)

            Text("x\(group.count)")
                .font(PicoTypography.countValue)
                .foregroundStyle(PicoColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(group.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(group.rowBorder, lineWidth: 1)
        )
    }

    private var fishIcon: some View {
        StoreFishIcon(
            group: group,
            size: 68,
            imagePadding: 0
        )
        .frame(width: 72, height: 72)
    }

    private var rarityTag: some View {
        Text(group.rarity.label)
            .font(PicoTypography.pill)
            .foregroundStyle(group.rarityStyle.pillTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, PicoSpacing.compact)
            .padding(.vertical, 5)
            .background(group.rarityStyle.pillBackgroundColor)
            .clipShape(Capsule(style: .continuous))
    }
}

private struct FishingIslandSelectionSection: View {
    let selectedIsland: PicoIsland
    let isSessionLocked: Bool
    let ownedIslandIDs: Set<String>
    let isLoading: Bool
    let summaries: [String: FishingIslandDiscoverySummary]
    let openStore: () -> Void
    let selectIsland: (PicoIsland) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                FishingCountIcon(name: "Map")
                    .frame(width: 24, height: 24)

                Text("Islands")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                }

                if isSessionLocked {
                    Text("Locked")
                        .font(PicoTypography.caption.weight(.bold))
                        .foregroundStyle(PicoColors.textSecondary)
                        .padding(.horizontal, PicoSpacing.compact)
                        .padding(.vertical, 5)
                        .background(PicoColors.softSurface.opacity(0.84))
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                let islands = PicoIsland.allCases

                ForEach(Array(islands.enumerated()), id: \.element.id) { index, island in
                    FishingIslandRow(
                        island: island,
                        isSelected: selectedIsland == island,
                        isSessionLocked: isSessionLocked,
                        isOwned: island == .original || ownedIslandIDs.contains(island.backendID),
                        summary: summaries[island.backendID] ?? FishingIslandDiscoverySummary(counts: nil),
                        openStore: openStore,
                        select: {
                            selectIsland(island)
                        }
                    )

                    if index < islands.count - 1 {
                        PicoCardDivider(horizontalPadding: 0)
                            .padding(.leading, 68)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PicoCreamCardStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
            )

            if isSessionLocked {
                Text("Island selection is locked during an open focus session.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FishingIslandRow: View {
    let island: PicoIsland
    let isSelected: Bool
    let isSessionLocked: Bool
    let isOwned: Bool
    let summary: FishingIslandDiscoverySummary
    let openStore: () -> Void
    let select: () -> Void

    var body: some View {
        Group {
            if isOwned {
                Button(action: select) {
                    rowContent {
                        statusIcon
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSessionLocked)
            } else {
                rowContent {
                    Button(action: openStore) {
                        Text("Buy in Store")
                            .lineLimit(1)
                        .font(PicoTypography.statusLabel)
                        .foregroundStyle(PicoColors.textOnPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(PicoColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func rowContent<Control: View>(@ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: PicoSpacing.standard) {
            FishingIslandSelectorIcon(island: island)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PicoSpacing.tiny) {
                    Text(island.displayName)
                        .font(PicoTypography.primaryLabel)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)

                    if !isOwned {
                        PicoIcon(.lockClosed, size: 12)
                            .foregroundStyle(PicoColors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }

                Text(subtitle)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: PicoSpacing.compact)

            control()
        }
        .padding(.horizontal, PicoSpacing.standard)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        summary.displayText
    }

    private var accessibilityLabel: String {
        if !isOwned {
            return "\(island.displayName), locked"
        }

        return "\(island.displayName), \(isSelected ? "selected" : "not selected")"
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !isOwned {
            PicoIcon(.lockClosed, size: 17)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(width: 28, height: 28)
        } else if isSessionLocked {
            PicoIcon(.lockClosed, size: 17)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(width: 28, height: 28)
        } else if isSelected {
            Image(systemName: "checkmark")
                .font(PicoTypography.symbol(size: 17, weight: .bold))
                .foregroundStyle(PicoColors.primary)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "chevron.right")
                .font(PicoTypography.symbol(size: 15, weight: .semibold))
                .foregroundStyle(PicoColors.textMuted)
                .frame(width: 28, height: 28)
        }
    }
}

private struct FishingIslandDiscoverySummary {
    let discoveredSpeciesCount: Int
    let totalSpeciesCount: Int
    let isLoaded: Bool

    init(counts: [FishCount]?) {
        guard let counts else {
            discoveredSpeciesCount = 0
            totalSpeciesCount = 0
            isLoaded = false
            return
        }

        discoveredSpeciesCount = counts.filter { $0.count > 0 }.count
        totalSpeciesCount = counts.count
        isLoaded = true
    }

    var displayText: String {
        guard isLoaded else { return "Loading species..." }
        guard totalSpeciesCount > 0 else { return "0 species discovered" }

        if discoveredSpeciesCount >= totalSpeciesCount {
            return "all species discovered!"
        }

        return "\(discoveredSpeciesCount)/\(totalSpeciesCount) species discovered"
    }
}

private struct FishingIslandSelectorIcon: View {
    let island: PicoIsland

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                    .fill(fallbackColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        Self.imageCache.object(forKey: island.rawValue as NSString) ?? Self.makeImage(for: island)
    }

    private var fallbackColor: Color {
        switch island {
        case .original:
            Color(hex: 0x7B8F62)
        case .sand:
            Color(hex: 0xE6C76F)
        }
    }

    private static let imageCache = NSCache<NSString, UIImage>()

    private static func makeImage(for island: PicoIsland) -> UIImage? {
        guard let image = island.selectorImageCandidates.lazy.compactMap({ UIImage(named: $0) }).first else {
            return nil
        }

        imageCache.setObject(image, forKey: island.rawValue as NSString)
        return image
    }
}

private extension PicoIsland {
    var collectionDisplayName: String {
        switch self {
        case .original:
            "Forest Island"
        case .sand:
            "Beach Island"
        }
    }

    var selectorImageCandidates: [String] {
        switch self {
        case .original:
            [
                "Icons/Mushroom_Poisones3",
                "Icons/Mushroom_Poisones3.png",
                "Mushroom_Poisones3",
                "Mushroom_Poisones3.png"
            ]
        case .sand:
            [
                "Icons/SandPile",
                "Icons/SandPile.png",
                "SandPile",
                "SandPile.png"
            ]
        }
    }
}

private enum FishingTier: String, CaseIterable, Identifiable {
    case common
    case rare
    case ultraRare = "ultra_rare"

    var id: String { rawValue }

    var rarity: FishRarity {
        FishRarity(rawValue: rawValue) ?? .common
    }

    var rarityStyle: PicoFishRarityStyle {
        rarity.picoStyle
    }

    nonisolated init?(rarity: FishRarity) {
        self.init(rawValue: rarity.rawValue)
    }
}

private extension FishRarity {
    var rarestFirstSortRank: Int {
        switch self {
        case .ultraRare:
            0
        case .rare:
            1
        case .common:
            2
        }
    }
}

private func bestRarityAnalyticsValue(in catches: [FishCatch]) -> String {
    catches
        .map(\.rarity)
        .sorted { $0.rarestFirstSortRank < $1.rarestFirstSortRank }
        .first?
        .rawValue ?? "none"
}

private func fishImageResourceCandidates(named assetName: String) -> [String] {
    let normalizedAssetName = normalizedFishAssetName(assetName)
    var assetNames: [String] = []

    func appendAssetNameVariants(_ name: String) {
        assetNames.appendIfMissing(name)

        let normalizedName = normalizedFishAssetName(name)
        assetNames.appendIfMissing(normalizedName)

        if let flatName = normalizedName.split(separator: "/").last.map(String.init) {
            assetNames.appendIfMissing(flatName)
        }
    }

    appendAssetNameVariants(assetName)

    if let alias = fishImageAssetAliases[normalizedAssetName] {
        appendAssetNameVariants(alias)
    }

    var candidates: [String] = []
    for name in assetNames {
        candidates.appendIfMissing("Icons/fish/\(name)")
        candidates.appendIfMissing("Icons/fish/\(name).png")
        candidates.appendIfMissing("fish/\(name)")
        candidates.appendIfMissing("fish/\(name).png")
        candidates.appendIfMissing(name)
        candidates.appendIfMissing("\(name).png")
    }

    return candidates
}

private func normalizedFishAssetName(_ assetName: String) -> String {
    var normalized = assetName

    if normalized.hasSuffix(".png") {
        normalized.removeLast(4)
    }

    for prefix in ["Icons/fish/", "fish/"] where normalized.hasPrefix(prefix) {
        normalized.removeFirst(prefix.count)
        break
    }

    return normalized
}

private func preferredFishImageAssetName(for fishID: FishID, assetName: String?) -> String {
    let fallbackAssetName = fishID.assetName
    guard let assetName, !assetName.isEmpty else { return fallbackAssetName }

    let normalizedAssetName = normalizedFishAssetName(assetName)
    return fishImageAssetAliases[normalizedAssetName] ?? normalizedAssetName
}

private let fishImageAssetAliases: [String: String] = [
    "carp": "freshwater/common_carp",
    "crucian": "freshwater/common_crucian",
    "pale_chub": "freshwater/common_pale_chub",
    "shad": "freshwater/common_shad",
    "angelfish": "freshwater/rare_angelfish",
    "leopoldi": "freshwater/rare_leopoldi",
    "sturgeon": "freshwater/rare_sturgeon",
    "arowana": "freshwater/super_rare_arowana",
    "pirarucu": "freshwater/super_rare_pirarucu",
    "anchovy": "saltwater/common_anchovy",
    "mackerel": "saltwater/common_mackerel",
    "sea_bass": "saltwater/common_sea_bass",
    "trevally": "saltwater/common_trevally",
    "blue_tang": "saltwater/rare_blue_tang",
    "clownfish": "saltwater/rare_clownfish",
    "pomfret": "saltwater/rare_pomfret",
    "great_white": "saltwater/super_rare_great_white",
    "whale_shark": "saltwater/super_rare_whale_shark",
    "bass": "freshwater/common_carp",
    "crab": "freshwater/common_crucian",
    "eel": "freshwater/common_pale_chub",
    "salmon": "freshwater/common_shad",
    "lobster": "freshwater/rare_angelfish",
    "pufferfish": "freshwater/rare_leopoldi",
    "dolphin": "freshwater/rare_sturgeon",
    "marlin": "freshwater/super_rare_arowana",
    "octopus": "freshwater/super_rare_pirarucu",
    "herring": "saltwater/common_anchovy",
    "shrimp": "saltwater/common_mackerel",
    "butterflyfish": "saltwater/common_sea_bass",
    "lionfish": "saltwater/common_trevally",
    "tuna": "saltwater/rare_blue_tang",
    "hammerhead": "saltwater/rare_pomfret",
    "sunfish": "saltwater/super_rare_whale_shark",
    "Fish_Bass": "freshwater/common_carp",
    "SeaShellfish_Crab_Red": "freshwater/common_crucian",
    "Fish_Eel": "freshwater/common_pale_chub",
    "Fish_Salmon": "freshwater/common_shad",
    "SeaShellfish_Lobster_Red": "freshwater/rare_angelfish",
    "Fish_PufferFish": "freshwater/rare_leopoldi",
    "SeaMammal_Dolphin": "freshwater/rare_sturgeon",
    "Fish_MarlinSwordfish": "freshwater/super_rare_arowana",
    "SeaInvertebrate_Octopus_Orange": "freshwater/super_rare_pirarucu",
    "Fish_Herring": "saltwater/common_anchovy",
    "SeaShellfish_Shrimp_Pink": "saltwater/common_mackerel",
    "TropicalFish_ButterflyFish": "saltwater/common_sea_bass",
    "TropicalFish_LionFish": "saltwater/common_trevally",
    "Fish_Tuna": "saltwater/rare_blue_tang",
    "Fish_GreatWhiteShark": "saltwater/super_rare_great_white",
    "Fish_HammerHeadShark": "saltwater/rare_pomfret",
    "Fish_Sunfish": "saltwater/super_rare_whale_shark"
]

private extension Array where Element == String {
    mutating func appendIfMissing(_ value: String) {
        guard !contains(value) else { return }
        append(value)
    }
}

private struct FishingCatalogFish: Identifiable {
    let seaCritterID: FishID
    let tier: FishingTier
    let displayName: String
    let assetName: String
    let sortOrder: Int

    var id: String {
        seaCritterID.rawValue
    }

    var imageResourceCandidates: [String] {
        fishImageResourceCandidates(named: assetName)
    }

    nonisolated init?(
        seaCritterID: FishID,
        tier: FishingTier,
        displayName: String,
        assetName: String,
        sortOrder: Int
    ) {
        self.seaCritterID = seaCritterID
        self.tier = tier
        self.displayName = displayName
        self.assetName = assetName
        self.sortOrder = sortOrder
    }

    nonisolated init?(catalogItem: FishCatalogItem) {
        guard let tier = FishingTier(rarity: catalogItem.rarity) else { return nil }

        self.init(
            seaCritterID: catalogItem.id,
            tier: tier,
            displayName: catalogItem.displayName,
            assetName: catalogItem.assetName,
            sortOrder: catalogItem.sortOrder
        )
    }

}

private struct FishingCollectionSections: View {
    let catalogFish: [FishingCatalogFish]
    let counts: [FishType: Int]

    private let columns = [
        GridItem(.flexible(), spacing: PicoSpacing.iconTextGap),
        GridItem(.flexible(), spacing: PicoSpacing.iconTextGap)
    ]

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: PicoSpacing.iconTextGap
        ) {
            ForEach(catalogFish) { catalogFish in
                FishingCollectionTile(
                    fish: catalogFish,
                    count: count(for: catalogFish)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PicoSpacing.compact)
        .padding(.top, PicoSpacing.compact)
        .padding(.bottom, PicoSpacing.compact)
    }

    private func count(for catalogFish: FishingCatalogFish) -> Int {
        counts[catalogFish.seaCritterID, default: 0]
    }
}

private struct FishingCollectionTile: View {
    let fish: FishingCatalogFish
    let count: Int

    private enum Layout {
        static let tileHeight: CGFloat = 188
        static let iconSize: CGFloat = 104
        static let iconFrameHeight: CGFloat = 104
        static let iconNameGap: CGFloat = 0
        static let nameHeight: CGFloat = 48
        static let nameFontSize: CGFloat = 27
        static let cornerBadgeInset: CGFloat = 14
        static let lockIconSize: CGFloat = 15
        static let lockIconFrameSize: CGFloat = 20
    }

    private var isUnlocked: Bool {
        count > 0
    }

    private var displayNameText: String {
        guard isUnlocked else { return "???" }
        return fish.displayName.fishingCollectionTileName
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: Layout.iconNameGap) {
                FishingCatalogIcon(
                    fish: fish,
                    isUnlocked: isUnlocked,
                    size: Layout.iconSize
                )
                .frame(height: Layout.iconFrameHeight)

                Text(displayNameText)
                    .font(PicoTypography.primary(size: Layout.nameFontSize, weight: .bold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.nameHeight, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, PicoSpacing.compact)

            countBadge
                .padding(.top, Layout.cornerBadgeInset)
                .padding(.trailing, Layout.cornerBadgeInset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.tileHeight)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(tileBorder, lineWidth: 1)
        )
    }

    private var tileBackground: Color {
        fish.tier.rarityStyle.rowBackgroundColor
    }

    private var tileBorder: Color {
        fish.tier.rarityStyle.rowBorderColor
    }

    private var countBadge: some View {
        Group {
            if isUnlocked {
                Text("×\(count)")
                    .font(PicoTypography.pill)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                PicoIcon(.lockClosed, size: Layout.lockIconSize)
                    .frame(width: Layout.lockIconFrameSize, height: Layout.lockIconFrameSize)
            }
        }
        .foregroundStyle(countBadgeForeground)
        .accessibilityLabel(Text(isUnlocked ? "\(count) caught" : "Locked"))
    }

    private var countBadgeForeground: Color {
        FishRarity.common.picoStyle.pillTextColor
    }
}

private extension String {
    var fishingCollectionTileName: String {
        guard !contains(" ") else { return self }
        return fishingCollectionSoftHyphenated
    }

    private var fishingCollectionSoftHyphenated: String {
        let softHyphen = "\u{00AD}"
        let lowercaseSelf = lowercased()
        let suffixes = ["fish", "head", "shark"]

        for suffix in suffixes where lowercaseSelf.hasSuffix(suffix) {
            let splitIndex = index(endIndex, offsetBy: -suffix.count)
            guard distance(from: startIndex, to: splitIndex) >= 4 else { continue }
            return "\(self[..<splitIndex])\(softHyphen)\(self[splitIndex...])"
        }

        return self
    }
}

private struct FishingCountIcon: View {
    let name: String
    var fallbackColor: Color = PicoColors.textSecondary

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(PicoTypography.symbol(size: 15, weight: .bold))
                    .foregroundStyle(fallbackColor)
            }
        }
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        [
            "Icons/\(name)",
            "Icons/\(name).png",
            "Icons/\(name.lowercased())",
            "Icons/\(name.lowercased()).png",
            name,
            "\(name).png",
            name.lowercased(),
            "\(name.lowercased()).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct FishingCatalogIcon: View {
    let fish: FishingCatalogFish
    let isUnlocked: Bool
    var size: CGFloat

    var body: some View {
        Group {
            if let fishImage {
                Image(uiImage: fishImage)
                    .resizable()
                    .scaledToFit()
                    .saturation(isUnlocked ? 1 : 0)
                    .brightness(isUnlocked ? 0 : -0.98)
                    .contrast(isUnlocked ? 1 : 1.8)
                    .opacity(1)
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: size * 0.66, weight: .bold))
                    .foregroundStyle(isUnlocked ? fish.tier.rarityStyle.iconFallbackColor : Color.black.opacity(0.94))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fishImage: UIImage? {
        fish.imageResourceCandidates.lazy.compactMap { UIImage(named: $0) }.first
    }
}

private struct StorePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var berryStore: BerryStore
    @EnvironmentObject private var fishStore: FishStore
    @EnvironmentObject private var islandStore: IslandStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    @State private var selectedMode: StoreMode = .buy
    @State private var previewedIsland: PicoIsland?
    @State private var previewedHatItem: StoreItem?
    @State private var sellingFishGroup: StoreFishGroup?

    private var islandItems: [StoreItem] {
        berryStore.storeCatalog
            .filter { $0.itemType == .island }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hatItems: [StoreItem] {
        berryStore.storeCatalog
            .filter { $0.itemType == .hat && $0.avatarHat != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var fishGroups: [StoreFishGroup] {
        StoreFishGroup.groups(
            from: fishStore.inventory,
            catalog: fishStore.fishCatalog,
            inventoryCounts: fishStore.inventoryCounts,
            saleMultiplier: picoPlusStore.capabilities.fishSaleBerryMultiplier
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                berryBalanceCard

                if let notice = berryStore.notice {
                    ProfileNoticeCard(text: notice)
                }

                if let notice = picoPlusStore.notice {
                    ProfileNoticeCard(text: notice)
                }

                if let notice = fishStore.notice {
                    ProfileNoticeCard(text: notice)
                }

                Picker("Store mode", selection: $selectedMode) {
                    ForEach(StoreMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch selectedMode {
                    case .buy:
                        StoreBuyCatalogSection(
                            islandItems: islandItems,
                            hatItems: hatItems,
                            ownedStoreItemIDs: sessionStore.ownedStoreItemIDs,
                            previewItem: preview
                        )
                    case .sell:
                        StoreFishSection(
                            groups: fishGroups,
                            isLoading: fishStore.isLoadingInventory,
                            isSelling: fishStore.isSellingFish,
                            presentSellSheet: presentSellSheet
                        )
                    }
                }
            }
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.vertical, PicoSpacing.section)
            .padding(.bottom, PicoSpacing.largeSection)
        }
        .picoScreenBackground()
        .fullScreenCover(item: $previewedIsland) { island in
            StoreIslandPreviewOverlay(
                island: island,
                item: islandItem(for: island),
                berryBalance: berryStore.balance.berries,
                ownedStoreItemIDs: sessionStore.ownedStoreItemIDs,
                purchasingStoreItemID: berryStore.purchasingStoreItemID,
                capabilities: picoPlusStore.capabilities,
                isPurchaseDisabled: berryStore.purchasingStoreItemID != nil
                    || berryStore.isLoadingBalance
                    || berryStore.isLoadingStoreCatalog
                    || sessionStore.session == nil,
                currentUserProfile: sessionStore.profile,
                catalog: fishStore.fishCatalog(for: island.backendID),
                isLoadingCatalog: fishStore.loadingFishCatalogIslandIDs.contains(island.backendID)
            ) {
                previewedIsland = nil
            } purchase: { item in
                purchase(item)
            }
            .task(id: island.backendID) {
                await fishStore.loadPreviewFishCatalog(
                    for: sessionStore.session,
                    islandID: island.backendID
                )
            }
            .onAppear {
                if sessionStore.profile == nil {
                    Task {
                        await sessionStore.loadProfileIfNeeded()
                    }
                }
            }
        }
        .fullScreenCover(item: $previewedHatItem) { item in
            StoreHatPreviewOverlay(
                item: item,
                hatItems: hatItems,
                berryBalance: berryStore.balance.berries,
                ownedStoreItemIDs: sessionStore.ownedStoreItemIDs,
                purchasingStoreItemID: berryStore.purchasingStoreItemID,
                capabilities: picoPlusStore.capabilities,
                isPurchaseDisabled: berryStore.purchasingStoreItemID != nil
                    || berryStore.isLoadingBalance
                    || berryStore.isLoadingStoreCatalog
                    || sessionStore.session == nil,
                currentUserProfile: sessionStore.profile,
                close: {
                    previewedHatItem = nil
                },
                purchase: purchase
            )
        }
        .sheet(item: $sellingFishGroup) { group in
            StoreFishSellSheet(
                group: group,
                isSelling: fishStore.isSellingFish,
                close: {
                    sellingFishGroup = nil
                },
                sell: { quantity in
                    sellFishGroup(group, quantity: quantity)
                }
            )
            .presentationDetents([.height(420)])
        }
        .task(id: islandStore.selectedIsland) {
            await sessionStore.loadProfileIfNeeded()
            await berryStore.loadBalance(for: sessionStore.session)
            await berryStore.loadStoreCatalog(for: sessionStore.session)
            if let ownedStoreItemIDs = await berryStore.loadStoreInventory(for: sessionStore.session) {
                sessionStore.applyOwnedStoreItemIDs(ownedStoreItemIDs)
                islandStore.updateOwnedIslandIDs(sessionStore.ownedIslandIDs)
            } else {
                berryStore.applyOwnedStoreItemIDs(sessionStore.ownedStoreItemIDs)
            }
            if fishStore.fishCatalog.isEmpty || fishStore.fishCatalogIslandID != islandStore.selectedIslandID {
                await fishStore.loadFishCatalog(
                    for: sessionStore.session,
                    islandID: islandStore.selectedIslandID
                )
            }
            await fishStore.loadInventoryCounts(for: sessionStore.session)
            await fishStore.loadInventory(for: sessionStore.session)
        }
    }

    private var berryBalanceCard: some View {
        HStack(alignment: .center, spacing: PicoSpacing.standard) {
            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text("Berries")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)

                BerryAmountLabel(
                    count: berryStore.balance.berries,
                    font: PicoTypography.sectionTitle,
                    iconSize: 24
                )
            }

            Spacer(minLength: 0)

            if berryStore.isLoadingBalance {
                ProgressView()
                    .tint(PicoColors.primary)
            }
        }
        .picoCreamCard(
            showsShadow: false,
            padding: PicoCreamCardStyle.contentPadding
        )
    }

    private func purchase(_ item: StoreItem) {
        Task {
            guard let result = await berryStore.purchaseStoreItem(item, for: sessionStore.session) else { return }
            sessionStore.applyOwnedStoreItemIDs(result.ownedStoreItemIDs)
            islandStore.updateOwnedIslandIDs(sessionStore.ownedIslandIDs)
        }
    }

    private func preview(_ item: StoreItem) {
        if let island = item.picoIsland {
            previewedIsland = island
        } else if item.avatarHat != nil {
            previewedHatItem = item
        }
    }

    private func islandItem(for island: PicoIsland) -> StoreItem? {
        islandItems.first { $0.picoIsland == island }
    }

    private func presentSellSheet(_ group: StoreFishGroup) {
        guard !fishStore.isSellingFish, !group.catches.isEmpty else { return }
        sellingFishGroup = group
    }

    private func sellFishGroup(_ group: StoreFishGroup, quantity: Int) {
        let selectedCatches = Array(group.catches.prefix(max(0, min(quantity, group.catches.count))))
        guard !selectedCatches.isEmpty else { return }

        sellingFishGroup = nil
        sellFish(selectedCatches)
    }

    private func sellFish(_ catches: [FishCatch]) {
        let catchIDs = catches.map(\.id)
        Task {
            guard let result = await fishStore.sellFish(catchIDs: catchIDs, for: sessionStore.session) else { return }
            Analytics.track(AnalyticsEvent(
                id: .fishSold,
                parameters: [
                    .fishCount: .int(result.soldFishCount),
                    .berriesEarned: .int(result.soldBerryAmount),
                    .bestRarity: .string(bestRarityAnalyticsValue(in: catches))
                ]
            ))
            berryStore.applyBalance(result.balance)
            await fishStore.loadInventoryCounts(for: sessionStore.session)
            await fishStore.loadInventory(for: sessionStore.session)
        }
    }
}

private enum StoreMode: String, CaseIterable, Identifiable {
    case buy
    case sell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buy:
            "Buy"
        case .sell:
            "Sell"
        }
    }
}

private struct StoreFishGroup: Identifiable {
    var id: FishID { seaCritterID }

    let seaCritterID: FishID
    let displayName: String
    let rarity: FishRarity
    let assetName: String
    let sortOrder: Int
    let unitValue: Int
    let saleMultiplier: Int
    let inventoryCount: Int?
    let catches: [FishCatch]

    var fishType: FishType {
        seaCritterID
    }

    var count: Int {
        inventoryCount ?? catches.count
    }

    var totalValue: Int {
        catches.reduce(0) { $0 + $1.sellValue * saleMultiplier }
    }

    var displayUnitValue: Int {
        unitValue * saleMultiplier
    }

    var imageResourceCandidates: [String] {
        fishImageResourceCandidates(named: assetName)
    }

    var rarityStyle: PicoFishRarityStyle {
        rarity.picoStyle
    }

    var rowBackground: Color {
        rarityStyle.rowBackgroundColor
    }

    var rowBorder: Color {
        rarityStyle.rowBorderColor
    }

    private var raritySortRank: Int {
        switch rarity {
        case .common:
            0
        case .rare:
            1
        case .ultraRare:
            2
        }
    }

    static func groups(
        from catches: [FishCatch],
        catalog: [FishCatalogItem],
        inventoryCounts: [FishCount],
        saleMultiplier: Int = 1
    ) -> [StoreFishGroup] {
        let resolvedSaleMultiplier = max(1, saleMultiplier)
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let inventoryCountByID = Dictionary(uniqueKeysWithValues: inventoryCounts.map { ($0.seaCritterID, $0) })

        return Dictionary(grouping: catches, by: \.seaCritterID)
            .map { seaCritterID, catches in
                let catalogItem = catalogByID[seaCritterID]
                let countItem = inventoryCountByID[seaCritterID]
                let firstCatch = catches.first
                let assetName = preferredFishImageAssetName(
                    for: seaCritterID,
                    assetName: catalogItem?.assetName ?? countItem?.assetName
                )

                return StoreFishGroup(
                    seaCritterID: seaCritterID,
                    displayName: catalogItem?.displayName ?? countItem?.displayName ?? seaCritterID.displayName,
                    rarity: catalogItem?.rarity ?? countItem?.rarity ?? firstCatch?.rarity ?? .common,
                    assetName: assetName,
                    sortOrder: catalogItem?.sortOrder ?? countItem?.sortOrder ?? Int.max,
                    unitValue: catalogItem?.sellValue ?? countItem?.sellValue ?? firstCatch?.sellValue ?? seaCritterID.sellValue,
                    saleMultiplier: resolvedSaleMultiplier,
                    inventoryCount: countItem?.count,
                    catches: catches
                )
            }
            .sorted { lhs, rhs in
                if lhs.raritySortRank != rhs.raritySortRank {
                    return lhs.raritySortRank > rhs.raritySortRank
                }

                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }
}

private struct StoreFishSection: View {
    let groups: [StoreFishGroup]
    let isLoading: Bool
    let isSelling: Bool
    let presentSellSheet: (StoreFishGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                FishingCountIcon(name: "Bucket")
                    .frame(width: 24, height: 24)

                Text("Inventory")
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                }
            }

            if groups.isEmpty && !isLoading {
                Text("No fish to sell yet.")
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PicoSpacing.tiny)
            } else {
                VStack(spacing: PicoSpacing.compact) {
                    ForEach(groups) { group in
                        StoreFishGroupRow(
                            group: group,
                            isSelling: isSelling,
                            openSellSheet: {
                                presentSellSheet(group)
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoreFishSellSheet: View {
    let group: StoreFishGroup
    let isSelling: Bool
    let close: () -> Void
    let sell: (Int) -> Void

    @State private var quantity: Int

    init(
        group: StoreFishGroup,
        isSelling: Bool,
        close: @escaping () -> Void,
        sell: @escaping (Int) -> Void
    ) {
        self.group = group
        self.isSelling = isSelling
        self.close = close
        self.sell = sell
        _quantity = State(initialValue: min(1, max(1, group.catches.count)))
    }

    private var maxQuantity: Int {
        max(1, group.catches.count)
    }

    private var selectedCatches: [FishCatch] {
        Array(group.catches.prefix(quantity))
    }

    private var totalValue: Int {
        selectedCatches.reduce(0) { $0 + $1.sellValue * group.saleMultiplier }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack {
                Spacer(minLength: 0)

                Button(action: close) {
                    PicoIcon(.xMarkRegular, size: 16)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(PicoColors.softSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }

            HStack(spacing: PicoSpacing.standard) {
                StoreFishIcon(
                    group: group,
                    size: 74,
                    imagePadding: 0
                )

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(group.displayName)
                        .font(PicoTypography.cardTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(group.count) available")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: PicoSpacing.compact) {
                quantityCard
                totalCard
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: PicoSpacing.compact) {
                Button("Cancel", action: close)
                    .buttonStyle(PicoSecondaryButtonStyle())
                    .disabled(isSelling)

                Button {
                    sell(quantity)
                } label: {
                    HStack(spacing: PicoSpacing.tiny) {
                        Text("Sell")

                        if isSelling {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(PicoColors.textOnPrimary)
                        }
                    }
                }
                .buttonStyle(PicoPrimaryButtonStyle())
                .disabled(isSelling || group.catches.isEmpty)
            }
        }
        .padding(PicoSpacing.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PicoColors.appBackground)
        .presentationBackground(PicoColors.appBackground)
        .presentationDragIndicator(.visible)
    }

    private var quantityCard: some View {
        HStack(spacing: PicoSpacing.compact) {
            Text("Quantity")
                .font(PicoTypography.primaryLabelSemibold)
                .foregroundStyle(PicoColors.textPrimary)

            Spacer(minLength: PicoSpacing.compact)

            HStack(spacing: PicoSpacing.compact) {
                quantityButton(systemName: "minus") {
                    quantity = max(1, quantity - 1)
                }
                .disabled(isSelling || quantity <= 1)

                Text("\(quantity)")
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 28)

                quantityButton(systemName: "plus") {
                    quantity = min(maxQuantity, quantity + 1)
                }
                .disabled(isSelling || quantity >= maxQuantity)
            }
        }
        .padding(PicoSpacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PicoColors.softSurface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
    }

    private var totalCard: some View {
        HStack(spacing: PicoSpacing.compact) {
            Text("Total")
                .font(PicoTypography.primaryLabelSemibold)
                .foregroundStyle(PicoColors.textPrimary)

            Spacer(minLength: PicoSpacing.compact)

            BerryAmountLabel(
                count: totalValue,
                font: PicoTypography.primaryLabelSemibold,
                iconSize: 18,
                textColor: PicoColors.textPrimary
            )
        }
        .padding(PicoSpacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PicoColors.softSurface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
    }

    private func quantityButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(PicoTypography.symbol(size: 13, weight: .bold))
                .foregroundStyle(PicoColors.textPrimary)
                .frame(width: 30, height: 30)
                .background(PicoColors.softSurface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct StoreFishGroupRow: View {
    let group: StoreFishGroup
    let isSelling: Bool
    let openSellSheet: () -> Void

    var body: some View {
        Button(action: openSellSheet) {
            HStack(spacing: PicoSpacing.standard) {
                fishIcon

                Text(group.displayName)
                    .font(PicoTypography.fishName)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)

                Spacer(minLength: PicoSpacing.compact)

                BerryAmountLabel(
                    count: group.displayUnitValue,
                    font: PicoTypography.primaryLabelSemibold,
                    iconSize: 16,
                    textColor: PicoColors.textPrimary
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(group.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .stroke(group.rowBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSelling || group.catches.isEmpty)
        .accessibilityLabel(Text("Sell \(group.displayName), \(formattedBerryCount(group.displayUnitValue)) each, \(group.count) available"))
    }

    private var fishIcon: some View {
        ZStack {
            StoreFishIcon(
                group: group,
                size: 68,
                imagePadding: 0
            )

            Text("x \(group.count)")
                .font(PicoTypography.pill)
                .foregroundStyle(PicoColors.textPrimary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(PicoColors.surface.opacity(0.92))
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(group.rowBorder, lineWidth: 1)
                )
                .offset(x: 2, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 72, height: 72)
    }
}

private struct StoreFishIcon: View {
    let group: StoreFishGroup
    var size: CGFloat
    var imagePadding: CGFloat = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: size * 0.62, weight: .bold))
                    .foregroundStyle(group.rarityStyle.iconFallbackColor)
            }
        }
        .padding(imagePadding)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        group.imageResourceCandidates.lazy.compactMap { UIImage(named: $0) }.first
    }
}

private struct StoreBuyCatalogSection: View {
    let islandItems: [StoreItem]
    let hatItems: [StoreItem]
    let ownedStoreItemIDs: Set<String>
    let previewItem: (StoreItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.section) {
            StoreItemSection(
                title: "Islands",
                icon: .map,
                items: islandItems,
                ownedStoreItemIDs: ownedStoreItemIDs,
                previewItem: previewItem
            )

            StoreItemSection(
                title: "Hats",
                icon: .hat,
                items: hatItems,
                ownedStoreItemIDs: ownedStoreItemIDs,
                previewItem: previewItem
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum StoreSectionIcon {
    case hat
    case map
    case system(String)
}

private struct StoreItemSection: View {
    let title: String
    let icon: StoreSectionIcon
    let items: [StoreItem]
    let ownedStoreItemIDs: Set<String>
    let previewItem: (StoreItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            StoreSectionHeader(title: title, icon: icon)

            if items.isEmpty {
                Text("No items available.")
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, PicoSpacing.tiny)
            } else {
                VStack(spacing: PicoSpacing.compact) {
                    ForEach(items) { item in
                        StoreItemRow(
                            item: item,
                            isOwned: ownedStoreItemIDs.contains(item.id),
                            preview: {
                                previewItem(item)
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoreItemRow: View {
    let item: StoreItem
    let isOwned: Bool
    let preview: () -> Void

    var body: some View {
        Button(action: preview) {
            rowContent(accessory: rowAccessory)
        }
        .buttonStyle(.plain)
        .padding(PicoSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var rowLabel: some View {
        HStack(spacing: PicoSpacing.standard) {
            itemIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)

                if item.isPaidOnly {
                    StorePicoPlusBadge()
                }
            }

            Spacer(minLength: PicoSpacing.compact)
        }
        .contentShape(Rectangle())
    }

    private func rowContent<Accessory: View>(accessory: Accessory) -> some View {
        HStack(spacing: PicoSpacing.standard) {
            rowLabel

            accessory
                .frame(width: 86, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var itemIcon: some View {
        if let hat = item.avatarHat {
            AvatarBadgeView(config: AvatarCatalog.defaultConfig.withHat(hat), size: 58)
        } else if let island = item.picoIsland {
            FishingIslandSelectorIcon(island: island)
                .frame(width: 58, height: 58)
        } else {
            Image(systemName: item.itemType == .island ? "map.fill" : "bag.fill")
                .font(PicoTypography.symbol(size: 28, weight: .semibold))
                .foregroundStyle(PicoColors.primary)
                .frame(width: 58, height: 58)
        }
    }

    @ViewBuilder
    private var rowAccessory: some View {
        if isOwned {
            HStack(spacing: PicoSpacing.tiny) {
                Text("✓")
                    .font(PicoTypography.statusLabel)

                Text("Owned")
                    .font(PicoTypography.statusLabel)
            }
            .foregroundStyle(PicoColors.primary.opacity(0.78))
            .frame(height: 34, alignment: .trailing)
        } else {
            priceLabel
        }
    }

    private var priceLabel: some View {
        BerryAmountLabel(
            count: item.berryPrice,
            font: PicoTypography.primaryLabelSemibold,
            iconSize: 16,
            textColor: PicoColors.textPrimary
        )
        .frame(height: 34, alignment: .trailing)
    }

}

private struct StorePicoPlusBadge: View {
    var body: some View {
        Text("Plus")
            .font(PicoTypography.tinyCaption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(PicoPlusGradientCapsuleBackground())
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.45), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Text("Pico Plus"))
    }
}

private extension StoreItem {
    func picoPlusPaywallSource(placement: PicoPlusPlacement) -> PicoPlusPaywallSource {
        .plusCosmetic(
            itemID: id,
            itemType: itemType.rawValue,
            itemKey: itemKey,
            placement: placement
        )
    }
}

private struct StoreSectionHeader: View {
    let title: String
    let icon: StoreSectionIcon

    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            switch icon {
            case .hat:
                hatIcon
            case .map:
                mapIcon
            case .system(let name):
                Image(systemName: name)
                    .font(PicoTypography.symbol(size: 20, weight: .semibold))
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
        }
    }

    @ViewBuilder
    private var mapIcon: some View {
        if let image = UIImage(named: "Map") ?? UIImage(named: "Icons/Map") ?? UIImage(named: "Icons/Map.png") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "map.fill")
                .font(PicoTypography.symbol(size: 20, weight: .semibold))
                .foregroundStyle(PicoColors.textSecondary)
                .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private var hatIcon: some View {
        if let image = UIImage(named: "Beanie_Yellow") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "hat.widebrim")
                .font(PicoTypography.symbol(size: 20, weight: .semibold))
                .foregroundStyle(PicoColors.textSecondary)
                .frame(width: 24, height: 24)
        }
    }
}

private struct StoreIslandPreviewOverlay: View {
    let island: PicoIsland
    let item: StoreItem?
    let berryBalance: Int
    let ownedStoreItemIDs: Set<String>
    let purchasingStoreItemID: String?
    let capabilities: PicoPlusCapabilities
    let isPurchaseDisabled: Bool
    let currentUserProfile: UserProfile?
    let catalog: [FishCatalogItem]
    let isLoadingCatalog: Bool
    let close: () -> Void
    let purchase: (StoreItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                PicoColors.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: PicoSpacing.standard) {
                        VStack(spacing: PicoSpacing.tiny) {
                            Text(island.displayName)
                                .font(PicoTypography.primary(size: 38, weight: .bold))
                                .foregroundStyle(PicoColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.64)

                            if let item {
                                if item.isPaidOnly {
                                    StorePicoPlusBadge()
                                }

                                BerryAmountLabel(
                                    count: item.berryPrice,
                                    font: PicoTypography.primaryLabelSemibold,
                                    iconSize: 16,
                                    textColor: PicoColors.textPrimary
                                )
                            }
                        }
                        .padding(.horizontal, 64)

                        StoreIslandMapPreview(
                            island: island,
                            currentUserProfile: currentUserProfile
                        )
                        .frame(
                            width: previewSize(in: proxy.size),
                            height: previewSize(in: proxy.size)
                        )

                        StoreIslandSpeciesGrid(
                            catalog: catalog,
                            isLoading: isLoadingCatalog
                        )
                        .padding(.horizontal, PicoSpacing.standard)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(
                        minHeight: max(
                            0,
                            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
                        ),
                        alignment: .center
                    )
                    .padding(.top, proxy.safeAreaInsets.top)
                    .padding(.bottom, PicoSpacing.standard)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let item {
                        StoreIslandPreviewPurchaseFooter(
                            item: item,
                            island: island,
                            berryBalance: berryBalance,
                            ownedStoreItemIDs: ownedStoreItemIDs,
                            purchasingStoreItemID: purchasingStoreItemID,
                            capabilities: capabilities,
                            isPurchaseDisabled: isPurchaseDisabled,
                            purchase: purchase,
                            close: close
                        )
                    }
                }

                Button(action: close) {
                    PicoIcon(.xMarkRegular, size: 18)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PicoColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close island preview"))
                .padding(PicoSpacing.standard)
            }
        }
    }

    private func previewSize(in size: CGSize) -> CGFloat {
        min(
            370,
            max(220, min(size.width - 24, size.height * 0.38))
        )
    }
}

private struct StoreIslandPreviewPurchaseFooter: View {
    let item: StoreItem
    let island: PicoIsland
    let berryBalance: Int
    let ownedStoreItemIDs: Set<String>
    let purchasingStoreItemID: String?
    let capabilities: PicoPlusCapabilities
    let isPurchaseDisabled: Bool
    let purchase: (StoreItem) -> Void
    let close: () -> Void

    private var isOwned: Bool {
        ownedStoreItemIDs.contains(item.id)
    }

    private var missingBerries: Int {
        max(0, item.berryPrice - berryBalance)
    }

    private var canPurchase: Bool {
        !isOwned && capabilities.canPurchaseStoreItem(item) && missingBerries == 0 && !isPurchaseDisabled
    }

    private var isPurchasing: Bool {
        purchasingStoreItemID == item.id
    }

    var body: some View {
        purchaseControl
            .frame(maxWidth: 360)
        .padding(.horizontal, PicoSpacing.standard)
        .padding(.top, PicoSpacing.compact)
        .padding(.bottom, PicoSpacing.standard)
        .frame(maxWidth: .infinity)
        .background(PicoColors.appBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PicoColors.border.opacity(0.72))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var purchaseControl: some View {
        if isOwned {
            HStack(spacing: PicoSpacing.tiny) {
                Text("✓")
                    .font(PicoTypography.statusLabel)

                Text("Owned")
                    .font(PicoTypography.statusLabel)
            }
            .foregroundStyle(PicoColors.primary.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 52)
        } else if !capabilities.canPurchaseStoreItem(item) {
            plusControl
        } else {
            Button {
                guard canPurchase else { return }
                purchase(item)
            } label: {
                HStack(spacing: PicoSpacing.tiny) {
                    Text("Buy")

                    if isPurchasing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(PicoColors.textOnPrimary)
                    }
                }
            }
            .buttonStyle(StoreIslandPreviewBuyButtonStyle())
            .disabled(!canPurchase)
            .accessibilityLabel(Text("Buy \(island.displayName)"))
            .accessibilityHint(Text(missingBerries > 0 ? "You need \(formattedBerryCount(missingBerries)) more." : ""))
        }
    }

    @ViewBuilder
    private var plusControl: some View {
        PicoPlusCTAButton(
            source: item.picoPlusPaywallSource(placement: .exclusiveHat),
            beforePresentation: closeBeforePresentation
        )
    }

    private func closeBeforePresentation() async {
        close()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}

private struct StoreIslandPreviewBuyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(isEnabled ? PicoColors.textOnPrimary : PicoColors.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(isEnabled ? PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1) : PicoColors.softSurface)
            )
    }
}

private struct StoreIslandSpeciesGrid: View {
    let catalog: [FishCatalogItem]
    let isLoading: Bool

    @State private var availableWidth: CGFloat = 0

    private enum Layout {
        static let columnCount = 3
        static let cardSpacing = PicoSpacing.compact
        static let fallbackCardSide: CGFloat = 96
        static let maxCardSide: CGFloat = 112
    }

    private var cardSide: CGFloat {
        guard availableWidth > 0 else { return Layout.fallbackCardSide }

        let totalSpacing = CGFloat(Layout.columnCount - 1) * Layout.cardSpacing
        return min(
            Layout.maxCardSide,
            max(0, (availableWidth - totalSpacing) / CGFloat(Layout.columnCount))
        )
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cardSide), spacing: Layout.cardSpacing),
            count: Layout.columnCount
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: PicoSpacing.standard) {
            Text(discoveryText)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, alignment: .center)

            if catalog.isEmpty {
                placeholder
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: Layout.cardSpacing) {
                    ForEach(catalog) { item in
                        StoreIslandSpeciesSilhouette(
                            item: item,
                            sideLength: cardSide
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: StoreIslandSpeciesGridWidthKey.self,
                        value: proxy.size.width
                    )
            }
        )
        .onPreferenceChange(StoreIslandSpeciesGridWidthKey.self) { width in
            availableWidth = width
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Available species silhouettes"))
    }

    private var discoveryText: String {
        let speciesCount = catalog.count
        return "\(speciesCount) new \(speciesCount == 1 ? "species" : "species") to discover!"
    }

    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.cardSpacing) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                        .fill(PicoColors.softSurface)
                        .frame(width: cardSide, height: cardSide)
                        .overlay {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(PicoColors.primary)
                        }
                }
            }
        } else {
            Text("No silhouettes available.")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
        }
    }
}

private struct StoreIslandSpeciesGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct StoreIslandSpeciesSilhouette: View {
    let item: FishCatalogItem
    let sideLength: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .foregroundStyle(Color.black.opacity(0.82))
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: 52, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
            }
        }
        .padding(PicoSpacing.standard)
        .frame(width: sideLength, height: sideLength)
        .background(item.rarity.picoStyle.rowBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(item.rarity.picoStyle.rowBorderColor, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        fishImageResourceCandidates(named: item.assetName)
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct StoreIslandMapPreview: View {
    let island: PicoIsland
    let currentUserProfile: UserProfile?

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: currentUserProfile,
            isFishingMode: true,
            mapStyle: island.mapStyle,
            maxTileWidth: 58
        )
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.large, style: .continuous))
        .accessibilityLabel(Text("\(island.displayName) preview"))
    }
}

private struct StoreHatPreviewOverlay: View {
    private static let scrubPointsPerStep: CGFloat = 30

    let hatItems: [StoreItem]
    let berryBalance: Int
    let ownedStoreItemIDs: Set<String>
    let purchasingStoreItemID: String?
    let capabilities: PicoPlusCapabilities
    let isPurchaseDisabled: Bool
    let currentUserProfile: UserProfile?
    let close: () -> Void
    let purchase: (StoreItem) -> Void

    @State private var selectedItem: StoreItem
    @State private var direction: AvatarPreviewDirection = .front
    @State private var scrubStartDirection: AvatarPreviewDirection?

    init(
        item: StoreItem,
        hatItems: [StoreItem],
        berryBalance: Int,
        ownedStoreItemIDs: Set<String>,
        purchasingStoreItemID: String?,
        capabilities: PicoPlusCapabilities,
        isPurchaseDisabled: Bool,
        currentUserProfile: UserProfile?,
        close: @escaping () -> Void,
        purchase: @escaping (StoreItem) -> Void
    ) {
        self.hatItems = hatItems
        self.berryBalance = berryBalance
        self.ownedStoreItemIDs = ownedStoreItemIDs
        self.purchasingStoreItemID = purchasingStoreItemID
        self.capabilities = capabilities
        self.isPurchaseDisabled = isPurchaseDisabled
        self.currentUserProfile = currentUserProfile
        self.close = close
        self.purchase = purchase
        _selectedItem = State(initialValue: item)
    }

    private var availableHatItems: [StoreItem] {
        hatItems.filter { $0.avatarHat != nil }
    }

    private var currentItem: StoreItem {
        availableHatItems.first { $0.id == selectedItem.id } ?? selectedItem
    }

    private var currentHat: AvatarHat {
        currentItem.avatarHat ?? .none
    }

    private var avatarConfig: AvatarConfig {
        (currentUserProfile?.avatarConfig ?? AvatarCatalog.defaultConfig).withHat(currentHat)
    }

    private var isOwned: Bool {
        ownedStoreItemIDs.contains(currentItem.id)
    }

    private var missingBerries: Int {
        max(0, currentItem.berryPrice - berryBalance)
    }

    private var canPurchase: Bool {
        !isOwned && capabilities.canPurchaseStoreItem(currentItem) && missingBerries == 0 && !isPurchaseDisabled
    }

    private var isPurchasing: Bool {
        purchasingStoreItemID == currentItem.id
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                PicoColors.appBackground
                    .ignoresSafeArea()

                VStack(spacing: PicoSpacing.standard) {
                    VStack(spacing: PicoSpacing.tiny) {
                        Text(currentItem.displayName)
                            .font(PicoTypography.primary(size: 38, weight: .bold))
                            .foregroundStyle(PicoColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.64)

                        BerryAmountLabel(
                            count: currentItem.berryPrice,
                            font: PicoTypography.primaryLabelSemibold,
                            iconSize: 16,
                            textColor: PicoColors.textPrimary
                        )
                    }
                    .padding(.horizontal, 64)

                    ZStack {
                        avatarPreview
                            .frame(height: avatarHeight(in: proxy.size))

                        HStack {
                            hatCycleButton(icon: .chevronLeftRegular, label: "Previous hat") {
                                selectHat(offset: -1)
                            }

                            Spacer(minLength: 0)

                            hatCycleButton(icon: .chevronRightRegular, label: "Next hat") {
                                selectHat(offset: 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, PicoSpacing.standard)

                    AvatarDirectionScrubRail(direction: $direction)
                        .frame(maxWidth: 188)
                        .frame(maxWidth: .infinity, alignment: .center)

                    purchaseControl
                        .frame(maxWidth: 320)
                        .padding(.horizontal, PicoSpacing.standard)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, proxy.safeAreaInsets.top + PicoSpacing.tiny)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, PicoSpacing.standard))

                Button(action: close) {
                    PicoIcon(.xMarkRegular, size: 18)
                        .foregroundStyle(PicoColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PicoColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close hat preview"))
                .padding(PicoSpacing.standard)
            }
        }
    }

    private var avatarPreview: some View {
        UserAvatar(
            config: avatarConfig,
            maxSpriteSide: 230,
            animationRow: direction.animationRow,
            isFlipped: direction.isFlipped
        )
        .contentShape(Rectangle())
        .gesture(avatarScrubGesture)
        .accessibilityLabel(Text("\(currentItem.displayName) preview"))
    }

    @ViewBuilder
    private var purchaseControl: some View {
        if isOwned {
            HStack(spacing: PicoSpacing.tiny) {
                Text("✓")
                    .font(PicoTypography.statusLabel)

                Text("Owned")
                    .font(PicoTypography.statusLabel)
            }
            .foregroundStyle(PicoColors.primary.opacity(0.78))
            .frame(maxWidth: .infinity, minHeight: 52)
        } else if !capabilities.canPurchaseStoreItem(currentItem) {
            plusControl
        } else {
            Button {
                guard canPurchase else { return }
                purchase(currentItem)
            } label: {
                HStack(spacing: PicoSpacing.tiny) {
                    Text("Buy")

                    if isPurchasing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(PicoColors.textOnPrimary)
                    }
                }
            }
            .buttonStyle(StoreHatPreviewBuyButtonStyle())
            .disabled(!canPurchase)
            .accessibilityHint(Text(missingBerries > 0 ? "You need \(formattedBerryCount(missingBerries)) more." : ""))
        }
    }

    @ViewBuilder
    private var plusControl: some View {
        PicoPlusCTAButton(
            source: currentItem.picoPlusPaywallSource(placement: .exclusiveHat),
            beforePresentation: closeBeforePresentation
        )
    }

    private func closeBeforePresentation() async {
        close()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func hatCycleButton(icon: PicoIconAsset, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PicoIcon(icon, size: 18)
                .foregroundStyle(availableHatItems.count >= 2 ? PicoColors.textPrimary : PicoColors.textMuted)
                .frame(width: 46, height: 46)
                .background(PicoColors.surface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(PicoColors.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(availableHatItems.count < 2)
        .accessibilityLabel(Text(label))
    }

    private var avatarScrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startDirection = scrubStartDirection ?? direction
                scrubStartDirection = startDirection
                let steps = Int((value.translation.width / Self.scrubPointsPerStep).rounded())
                direction = startDirection.rotated(by: steps)
            }
            .onEnded { _ in
                scrubStartDirection = nil
            }
    }

    private func selectHat(offset: Int) {
        let items = availableHatItems
        guard items.count >= 2 else { return }

        guard let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }) else {
            selectedItem = items[0]
            return
        }

        let nextIndex = (currentIndex + offset + items.count) % items.count
        selectedItem = items[nextIndex]
    }

    private func avatarHeight(in size: CGSize) -> CGFloat {
        min(270, max(210, size.height * 0.36))
    }
}

private struct StoreHatPreviewBuyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(isEnabled ? PicoColors.textOnPrimary : PicoColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(isEnabled ? PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1) : PicoColors.softSurface)
            )
    }
}

private struct StoreHatsSectionHeader: View {
    var body: some View {
        StoreSectionHeader(title: "Hats", icon: .hat)
    }
}

private struct StoreBuyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(isEnabled ? PicoColors.textOnPrimary : PicoColors.primary.opacity(0.38))
            .frame(width: 68, height: 38)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(isEnabled ? PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1) : PicoColors.softSurface.opacity(0.72))
            )
    }
}

private struct ProfilePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore
    let openStore: () -> Void
    @State private var username = ""
    @State private var displayName = ""
    @State private var draftDisplayName = ""
    @State private var avatarConfig = AvatarCatalog.defaultConfig
    @State private var avatarDirection: AvatarPreviewDirection = .front
    @State private var isNameEditorPresented = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: PicoSpacing.standard) {
                    profileContent

                    if sessionStore.profile != nil {
                        ProfileAvatarOutfitCard(
                            selection: $avatarConfig,
                            direction: $avatarDirection,
                            ownedHats: sessionStore.ownedHats,
                            canCycleHats: availableHats.count >= 2,
                            showsSaveButton: hasProfileChanges,
                            canSave: canSave,
                            isSaving: sessionStore.isProfileSaving,
                            previousHat: selectPreviousHat,
                            nextHat: selectNextHat,
                            buyInStore: openStore,
                            subscribeToPlus: subscribeToPlusForSelectedHat,
                            save: saveProfile
                        )
                    }

                    if let profileNotice = sessionStore.profileNotice {
                        ProfileNoticeCard(text: profileNotice)
                    }

                    Spacer(minLength: PicoSpacing.largeSection)

                    ProfileSignOutBar {
                        sessionStore.signOut()
                    }
                    .padding(.top, PicoSpacing.section)
                }
                .frame(minHeight: max(0, geometry.size.height - PicoSpacing.largeSection), alignment: .top)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.vertical, PicoSpacing.section)
                .padding(.bottom, PicoSpacing.largeSection)
            }
        }
        .picoScreenBackground()
        .task {
            await sessionStore.loadProfileIfNeeded()
            syncEditableProfile()
        }
        .onChange(of: sessionStore.profile) {
            syncEditableProfile()
        }
        .sheet(isPresented: $isNameEditorPresented) {
            if let profile = sessionStore.profile {
                ProfileNameEditorSheet(
                    profile: profile,
                    displayName: $draftDisplayName
                ) {
                    displayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    isNameEditorPresented = false
                } cancel: {
                    isNameEditorPresented = false
                }
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(PicoColors.appBackground)
                .presentationCornerRadius(PicoCreamCardStyle.sheetCornerRadius)
            }
        }
    }

    @ViewBuilder
    private var profileContent: some View {
        if let profile = sessionStore.profile {
            Button {
                draftDisplayName = displayName
                isNameEditorPresented = true
            } label: {
                ProfileCardView(
                    profile: profile,
                    username: username,
                    displayName: displayName,
                    avatarConfig: avatarConfig
                )
            }
            .buttonStyle(.plain)
        } else if sessionStore.isProfileLoading {
            ProgressView("Loading profile")
                .font(PicoTypography.caption)
                .tint(PicoColors.primary)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .picoCreamCard(
                    showsShadow: false,
                    padding: PicoCreamCardStyle.contentPadding
                )
        } else {
            ProfileUnavailableView()
                .picoCreamCard(
                    showsShadow: false,
                    padding: PicoCreamCardStyle.contentPadding
                )
        }
    }

    private var canSave: Bool {
        guard sessionStore.profile != nil else { return false }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidDisplayName = (1...40).contains(normalizedDisplayName.count)
        let hasOwnedHat = avatarConfig.selectedHat.isOwned(in: sessionStore.ownedHats)
        return hasValidDisplayName && hasOwnedHat && hasProfileChanges
    }

    private var hasProfileChanges: Bool {
        guard let profile = sessionStore.profile else { return false }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedDisplayName != profile.displayName
            || avatarConfig != profile.avatarConfig
    }

    private var availableHats: [AvatarHat] {
        AvatarHat.allCases
    }

    private func syncEditableProfile() {
        guard let profile = sessionStore.profile else { return }
        username = profile.username
        displayName = profile.displayName
        draftDisplayName = profile.displayName
        avatarConfig = profile.avatarConfig
    }

    private func selectPreviousHat() {
        selectHat(offset: -1)
    }

    private func selectNextHat() {
        selectHat(offset: 1)
    }

    private func selectHat(offset: Int) {
        let hats = availableHats
        guard hats.count >= 2 else { return }

        guard let currentIndex = hats.firstIndex(of: avatarConfig.selectedHat) else {
            avatarConfig = avatarConfig.withHat(hats[0])
            return
        }

        let nextIndex = (currentIndex + offset + hats.count) % hats.count
        avatarConfig = avatarConfig.withHat(hats[nextIndex])
    }

    private func saveProfile() {
        Task {
            await sessionStore.updateProfile(
                displayName: displayName,
                avatarConfig: avatarConfig
            )
        }
    }

    private func subscribeToPlusForSelectedHat(placement: PicoPlusPlacement) {
        let hat = avatarConfig.selectedHat
        Task {
            await picoPlusStore.presentPaywall(
                source: .plusCosmetic(
                    itemID: "hat:\(hat.rawValue)",
                    itemType: StoreItemType.hat.rawValue,
                    itemKey: "\(hat.rawValue)",
                    placement: placement
                ),
                authSession: sessionStore.session
            )

            if picoPlusStore.capabilities.canPurchasePaidOnlyStoreItems {
                openStore()
            }
        }
    }
}

private struct UserAvatar: View {
    let config: AvatarConfig
    var maxSpriteSide: CGFloat = 150
    var usesHappyIdle = false
    var scarf: AvatarScarf? = nil
    var animationRow = 0
    var isFlipped = false

    var body: some View {
        TransparentUserAvatarView(
            hat: config.selectedHat,
            maxSpriteSide: maxSpriteSide,
            usesHappyIdle: usesHappyIdle,
            scarf: scarf,
            animationRow: animationRow,
            isFlipped: isFlipped
        )
        .accessibilityLabel(Text("User character"))
    }
}

private struct TransparentUserAvatarView: UIViewRepresentable {
    let hat: AvatarHat
    let maxSpriteSide: CGFloat
    let usesHappyIdle: Bool
    let scarf: AvatarScarf?
    let animationRow: Int
    let isFlipped: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear

        let scene = UserAvatarScene(size: .zero)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear

        let scene: UserAvatarScene
        if let existingScene = view.scene as? UserAvatarScene {
            scene = existingScene
        } else {
            let newScene = UserAvatarScene(size: view.bounds.size)
            newScene.scaleMode = .resizeFill
            newScene.backgroundColor = .clear
            view.presentScene(newScene)
            scene = newScene
        }

        scene.size = view.bounds.size
        scene.configure(
            hat: hat,
            maxSpriteSide: maxSpriteSide,
            usesHappyIdle: usesHappyIdle,
            scarf: scarf,
            animationRow: animationRow,
            isFlipped: isFlipped
        )
    }
}

private final class UserAvatarScene: SKScene {
    private static let idleActionKey = "idle"

    private var hat: AvatarHat = .none
    private var maxSpriteSide: CGFloat = 150
    private var usesHappyIdle = false
    private var scarf: AvatarScarf?
    private var animationRow = 0
    private var isFlipped = false
    private var renderedConfig: RenderConfig?
    private var sprite: AvatarLayeredSpriteNode?

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        redrawIfNeeded()
    }

    func configure(
        hat: AvatarHat,
        maxSpriteSide: CGFloat,
        usesHappyIdle: Bool,
        scarf: AvatarScarf?,
        animationRow: Int,
        isFlipped: Bool
    ) {
        self.hat = hat
        self.maxSpriteSide = maxSpriteSide
        self.usesHappyIdle = usesHappyIdle
        self.scarf = scarf
        self.animationRow = animationRow
        self.isFlipped = isFlipped
        redrawIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redrawIfNeeded()
    }

    private func redrawIfNeeded() {
        guard size.width > 0, size.height > 0 else { return }

        let nextConfig = RenderConfig(
            size: size,
            hat: hat,
            maxSpriteSide: maxSpriteSide,
            usesHappyIdle: usesHappyIdle,
            scarf: scarf,
            animationRow: animationRow,
            isFlipped: isFlipped
        )
        guard nextConfig != renderedConfig else { return }
        renderedConfig = nextConfig

        let frames: AvatarLayeredFrames
        if usesHappyIdle {
            frames = AvatarHappyIdleFrames(hat: hat, scarf: scarf).layeredFrames
        } else {
            frames = AvatarIdleFrames(hat: hat, scarf: scarf).layeredFrames
        }

        let sprite = sprite ?? AvatarLayeredSpriteNode(frames: frames)
        if self.sprite == nil {
            self.sprite = sprite
            addChild(sprite)
        }
        let spriteSide = min(size.width * 0.72, size.height * 0.90, maxSpriteSide)
        sprite.spriteSize = CGSize(width: spriteSide, height: spriteSide)
        sprite.xScale = isFlipped ? -abs(sprite.xScale) : abs(sprite.xScale)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.removeAnimation(forKey: Self.idleActionKey)
        sprite.runAnimation(
            with: frames,
            row: animationRow,
            timePerFrame: 0.10,
            key: Self.idleActionKey
        )
    }

    private struct RenderConfig: Equatable {
        let size: CGSize
        let hat: AvatarHat
        let maxSpriteSide: CGFloat
        let usesHappyIdle: Bool
        let scarf: AvatarScarf?
        let animationRow: Int
        let isFlipped: Bool
    }
}

private struct ProfileCardView: View {
    let profile: UserProfile
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig

    var body: some View {
        HStack(spacing: 14) {
            AvatarBadgeView(config: avatarConfig, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)

                Text("@\(username)")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
        .picoCreamCard(
            showsShadow: false,
            padding: PicoCreamCardStyle.contentPadding
        )
        .accessibilityLabel(Text("\(displayName), @\(username), edit profile"))
    }
}

private enum AvatarPreviewDirection: Int, CaseIterable, Identifiable {
    case front
    case frontRight
    case right
    case backRight
    case back
    case backLeft
    case left
    case frontLeft

    var id: Int { rawValue }

    var animationRow: Int {
        switch self {
        case .front:
            0
        case .frontRight, .frontLeft:
            1
        case .right, .left:
            2
        case .backRight, .backLeft:
            3
        case .back:
            4
        }
    }

    var isFlipped: Bool {
        switch self {
        case .frontRight, .right, .backRight:
            true
        case .front, .back, .backLeft, .left, .frontLeft:
            false
        }
    }

    var systemImage: String {
        switch self {
        case .front:
            "arrow.down"
        case .frontRight:
            "arrow.down.right"
        case .right:
            "arrow.right"
        case .backRight:
            "arrow.up.right"
        case .back:
            "arrow.up"
        case .backLeft:
            "arrow.up.left"
        case .left:
            "arrow.left"
        case .frontLeft:
            "arrow.down.left"
        }
    }

    var accessibilityName: String {
        switch self {
        case .front:
            "Front"
        case .frontRight:
            "Front right"
        case .right:
            "Right"
        case .backRight:
            "Back right"
        case .back:
            "Back"
        case .backLeft:
            "Back left"
        case .left:
            "Left"
        case .frontLeft:
            "Front left"
        }
    }

    func rotated(by steps: Int) -> Self {
        let count = Self.allCases.count
        let nextIndex = (rawValue + steps % count + count) % count
        return Self.allCases[nextIndex]
    }

    mutating func rotateClockwise() {
        self = rotated(by: 1)
    }

    mutating func rotateCounterclockwise() {
        self = rotated(by: -1)
    }
}

private struct ProfileAvatarOutfitCard: View {
    private static let scrubPointsPerStep: CGFloat = 30

    @Binding var selection: AvatarConfig
    @Binding var direction: AvatarPreviewDirection
    let ownedHats: Set<AvatarHat>
    let canCycleHats: Bool
    let showsSaveButton: Bool
    let canSave: Bool
    let isSaving: Bool
    let previousHat: () -> Void
    let nextHat: () -> Void
    let buyInStore: () -> Void
    let subscribeToPlus: (PicoPlusPlacement) -> Void
    let save: () -> Void
    @State private var scrubStartDirection: AvatarPreviewDirection?

    private var selectedHatIsOwned: Bool {
        selection.selectedHat.isOwned(in: ownedHats)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            UserAvatar(
                config: selection,
                animationRow: direction.animationRow,
                isFlipped: direction.isFlipped
            )
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .contentShape(Rectangle())
            .gesture(avatarScrubGesture)
            .overlay(alignment: .topLeading) {
                if !selectedHatIsOwned {
                    if selection.selectedHat.isPicoPlusExclusive {
                        ProfileSubscribeToPlusPillButton(action: subscribeToPlus)
                            .padding(.top, PicoSpacing.compact)
                            .padding(.leading, PicoSpacing.compact)
                    } else {
                        ProfileBuyInStorePillButton(action: buyInStore)
                            .padding(.top, PicoSpacing.compact)
                            .padding(.leading, PicoSpacing.compact)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !selectedHatIsOwned {
                    PicoIcon(.lockClosed, size: 17)
                        .foregroundStyle(PicoColors.textOnPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(PicoColors.textPrimary.opacity(0.76)))
                        .overlay {
                            Circle()
                                .stroke(PicoColors.textOnPrimary.opacity(0.24), lineWidth: 1)
                        }
                        .padding(.top, PicoSpacing.compact)
                        .padding(.trailing, PicoSpacing.compact)
                        .accessibilityLabel(Text("Hat locked"))
                }
            }
            .padding(.top, PicoSpacing.compact)
            .padding(.horizontal, PicoSpacing.compact)

            AvatarDirectionScrubRail(direction: $direction)
                .frame(maxWidth: 188)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()
                .overlay(PicoColors.border)

            HStack(spacing: PicoSpacing.standard) {
                StoreHatsSectionHeader()

                Spacer(minLength: 0)

                HStack(spacing: PicoSpacing.compact) {
                    hatButton(icon: .chevronLeftRegular, action: previousHat)
                    hatButton(icon: .chevronRightRegular, action: nextHat)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: PicoSpacing.standard) {
                    ForEach(AvatarHat.allCases) { hat in
                        hatCollectionItem(hat)
                    }
                }
            }

            if showsSaveButton {
                HStack {
                    Spacer(minLength: 0)

                    Button(action: save) {
                        HStack(spacing: PicoSpacing.tiny) {
                            Text("Save")

                            if isSaving {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(PicoColors.primary)
                            }
                        }
                        .font(PicoTypography.primaryLabelSemibold)
                        .foregroundStyle(canSave && !isSaving ? PicoColors.primary : PicoColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || isSaving)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .picoCreamCard(
            showsShadow: false,
            padding: PicoCreamCardStyle.contentPadding
        )
    }

    private func hatButton(icon: PicoIconAsset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PicoIcon(icon, size: 17)
                .foregroundStyle(canCycleHats ? PicoColors.textPrimary : PicoColors.textMuted)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(!canCycleHats)
    }

    private var avatarScrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startDirection = scrubStartDirection ?? direction
                scrubStartDirection = startDirection
                let steps = Int((value.translation.width / Self.scrubPointsPerStep).rounded())
                direction = startDirection.rotated(by: steps)
            }
            .onEnded { _ in
                scrubStartDirection = nil
            }
    }

    private func hatCollectionItem(_ hat: AvatarHat) -> some View {
        let isSelected = selection.selectedHat == hat
        let isOwned = hat.isOwned(in: ownedHats)

        return Button {
            selection = selection.withHat(hat)
        } label: {
            VStack(spacing: PicoSpacing.compact) {
                AvatarBadgeView(config: selection.withHat(hat), size: 58)
                    .overlay {
                        if isSelected {
                            Circle()
                                .stroke(PicoColors.primary, lineWidth: 3)
                        }
                    }
                    .overlay {
                        if !isOwned {
                            Circle()
                                .fill(.black.opacity(0.42))

                            PicoIcon(.lockClosed, size: 17)
                                .foregroundStyle(PicoColors.textOnPrimary)
                        }
                    }
                    .frame(width: 66, height: 66, alignment: .center)

                Text(hat.name)
                    .font(PicoTypography.caption)
                    .foregroundStyle(isSelected ? PicoColors.textPrimary : PicoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if !isOwned && hat.isPicoPlusExclusive {
                    StorePicoPlusBadge()
                } else if !isOwned {
                    Text("Not owned")
                        .font(PicoTypography.tinyCaption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(width: 82, height: 120, alignment: .top)
            .contentShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))
            .opacity(isOwned ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isOwned ? "\(hat.name) hat" : "\(hat.name) hat, not owned"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProfileBuyInStorePillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Buy in store")
                .font(PicoTypography.statusLabel)
                .foregroundStyle(PicoColors.textOnPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PicoColors.primary)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text("Buy selected hat in store"))
    }
}

private struct ProfileSubscribeToPlusPillButton: View {
    let action: (PicoPlusPlacement) -> Void

    var body: some View {
        Button {
            action(.exclusiveHat)
        } label: {
            Text("Buy in store")
                .font(PicoTypography.statusLabel)
                .foregroundStyle(PicoColors.textOnPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PicoColors.primary)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(Text("Buy selected hat in shop"))
    }
}

private struct AvatarDirectionScrubRail: View {
    @Binding var direction: AvatarPreviewDirection

    private let thumbSize: CGFloat = 18
    private let trackHeight: CGFloat = 4
    private let hitHeight: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let centerY = hitHeight / 2
            let activeX = xPosition(for: direction.rawValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PicoColors.softSurface.opacity(0.86))
                    .frame(height: trackHeight)
                    .position(x: width / 2, y: centerY)

                ForEach(AvatarPreviewDirection.allCases) { railDirection in
                    let isActive = railDirection == direction

                    Circle()
                        .fill(isActive ? PicoColors.border : PicoColors.border.opacity(0.72))
                        .frame(width: isActive ? 10 : 6, height: isActive ? 10 : 6)
                        .position(
                            x: xPosition(for: railDirection.rawValue, width: width),
                            y: centerY
                        )
                }

                Circle()
                    .fill(PicoColors.border)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Circle()
                            .stroke(PicoColors.textMuted.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: PicoColors.textMuted.opacity(0.22), radius: 6, x: 0, y: 3)
                    .position(x: activeX, y: centerY)
            }
            .frame(width: width, height: hitHeight)
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: width))
            .accessibilityElement()
            .accessibilityLabel(Text("Rotate character"))
            .accessibilityValue(Text(direction.accessibilityName))
            .accessibilityAdjustableAction { adjustmentDirection in
                switch adjustmentDirection {
                case .increment:
                    direction.rotateClockwise()
                case .decrement:
                    direction.rotateCounterclockwise()
                @unknown default:
                    break
                }
            }
        }
        .frame(height: hitHeight)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                direction = direction(at: value.location.x, width: width)
            }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        let count = CGFloat(max(AvatarPreviewDirection.allCases.count - 1, 1))
        let inset = thumbSize / 2
        return inset + (width - thumbSize) * CGFloat(index) / count
    }

    private func direction(at x: CGFloat, width: CGFloat) -> AvatarPreviewDirection {
        let count = AvatarPreviewDirection.allCases.count
        let inset = thumbSize / 2
        let usableWidth = max(1, width - thumbSize)
        let progress = min(max((x - inset) / usableWidth, 0), 1)
        let index = Int((progress * CGFloat(count - 1)).rounded())
        return AvatarPreviewDirection.allCases[index]
    }
}

private struct ProfileNameEditorSheet: View {
    let profile: UserProfile
    @Binding var displayName: String
    let save: () -> Void
    let cancel: () -> Void

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDisplayNameValid: Bool {
        (1...40).contains(normalizedDisplayName.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            Text("Display Name")
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)

            Text("@\(profile.username)")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)

            TextField(
                "",
                text: $displayName,
                prompt: Text("Display name").foregroundStyle(PicoColors.textMuted)
            )
                .textContentType(.name)
                .autocorrectionDisabled()
                .font(PicoTypography.body)
                .foregroundStyle(PicoColors.textPrimary)
                .padding(.horizontal, PicoSpacing.standard)
                .frame(height: 52)
                .background(PicoCreamCardStyle.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))

            HStack(spacing: PicoSpacing.compact) {
                Button("Cancel", action: cancel)
                    .buttonStyle(PicoCreamBorderedButtonStyle())

                Button("Save", action: save)
                    .buttonStyle(PicoPrimaryButtonStyle())
                    .disabled(!isDisplayNameValid)
                    .opacity(isDisplayNameValid ? 1 : 0.62)
            }
        }
        .padding(PicoSpacing.section)
        .picoScreenBackground()
    }
}

private struct ProfileNoticeCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PicoTypography.caption)
            .foregroundStyle(PicoColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.contentPadding
            )
    }
}

private struct ProfileSignOutBar: View {
    let signOut: () -> Void

    var body: some View {
        Button(role: .destructive, action: signOut) {
            HStack(spacing: PicoSpacing.tiny) {
                PicoIcon(.logoutRegular, size: 18)
                Text("Sign Out")
            }
                .font(PicoTypography.primaryLabelSemibold)
                .foregroundStyle(PicoColors.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PicoSpacing.standard)
        }
        .buttonStyle(.plain)
        .background(PicoColors.appBackground)
    }
}

private struct ProfileUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            HStack(spacing: PicoSpacing.compact) {
                PicoIcon(.userCircleRegular, size: 28)
                Text("Profile unavailable")
            }
            .font(PicoTypography.primaryLabelSemibold)
            .foregroundStyle(PicoColors.textPrimary)
        } description: {
            Text("Your public profile could not be loaded.")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
        }
    }
}

private struct PlaceholderDetailView: View {
    let title: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "rectangle.stack")
        } description: {
            Text("This view is ready to be extended.")
        }
        .navigationTitle(title)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDisplayName("Logged Out")

            AppShellView()
                .environmentObject(AuthSessionStore.preview(session: AuthSession.preview))
                .previewDisplayName("Logged In")
        }
    }
}
#endif
