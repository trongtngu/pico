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
        }
        .animation(.snappy(duration: 0.22), value: isNavigationDrawerOpen)
        .tint(PicoColors.primary)
        .environmentObject(friendStore)
        .environmentObject(focusStore)
        .environmentObject(villageStore)
        .environmentObject(bondRewardClaimStore)
        .environmentObject(berryStore)
        .environmentObject(fishStore)
        .task(id: sessionStore.session?.user?.id) {
            await sessionStore.refreshSessionIfNeeded()
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
        .onChange(of: focusStore.resultSession) {
            guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return }
            Task {
                await villageStore.loadResidents(for: sessionStore.session)
                await berryStore.loadBalance(for: sessionStore.session)
                if fishStore.fishCatalog.isEmpty {
                    await fishStore.loadFishCatalog(for: sessionStore.session)
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
                if fishStore.fishCatalog.isEmpty {
                    await fishStore.loadFishCatalog(for: sessionStore.session)
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

    var body: some View {
        VStack(alignment: isPersistent ? .center : .leading, spacing: PicoSpacing.compact) {
            if !isPersistent {
                Text("pico")
                    .font(PicoTypography.sectionTitle)
                    .foregroundStyle(PicoColors.textPrimary)
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
    case bonds
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Village"
        case .fishing:
            "Fishing"
        case .store:
            "Store"
        case .bonds:
            "Bonds"
        case .friends:
            "Friends"
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
        case .bonds:
            isSelected ? .sparklesSolid : .sparklesRegular
        case .friends:
            isSelected ? .usersSolid : .usersRegular
        case .settings:
            isSelected ? .userCircleSolid : .userCircleRegular
        }
    }

    @ViewBuilder
    func rootView(
        openFocus: @escaping () -> Void,
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
            FishingPage()
        case .store:
            StorePage()
        case .bonds:
            BondsPage()
        case .friends:
            FriendsPage()
        case .settings:
            ProfilePage()
        }
    }
}

private struct HomePage: View {
    @EnvironmentObject private var focusStore: FocusStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var berryStore: BerryStore
    @EnvironmentObject private var fishStore: FishStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var sessionStore: AuthSessionStore
    let showsMenuButton: Bool
    let openNavigation: () -> Void
    @State private var isStartFocusSheetPresented = false
    @State private var startFocusStep = StartFocusSheetStep.modePicker
    @State private var startFocusSheetHeight: CGFloat = 360
    @State private var fishCatchSheetHeight: CGFloat = 430
    @State private var isFishCatchSheetPresented = false
    @State private var isFocusResultOverlayDismissed = false
    @State private var villageMapStyle: VillageMapStyle = .originalIsland

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ScrollView {
                    GeometryReader { viewport in
                        VStack(spacing: PicoSpacing.compact) {
                            VillageHeroSection(
                                residents: gridResidents,
                                currentUserProfile: sessionStore.profile,
                                isLoading: villageStore.isLoadingResidents,
                                notice: villageStore.notice,
                                isFishingMode: focusStore.activeSession != nil,
                                mapStyle: villageMapStyle,
                                height: villageHeight(for: viewport.size.height)
                            )
                            .gesture(villageMapSwipeGesture)

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
                        openNavigation: openNavigation
                    )
                }
            }
            .allowsHitTesting(!showsFocusResultOverlay)

            if showsFocusResultOverlay, let resultSession = focusStore.resultSession {
                FocusCompleteOverlay(
                    session: resultSession,
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
        .sheet(isPresented: $isFishCatchSheetPresented, onDismiss: finishFishCatchFlow) {
            FishCatchSuccessSheet(
                catches: fishStore.currentSessionCatches,
                catalog: fishStore.fishCatalog,
                isLoading: fishStore.isLoadingSessionCatches,
                notice: fishStore.notice,
                measuredHeight: $fishCatchSheetHeight,
                onRetry: retryCompletedSessionFishFetch,
                onDone: {
                    isFishCatchSheetPresented = false
                }
            )
            .presentationDetents(fishCatchSheetDetents)
            .presentationDragIndicator(.visible)
            .presentationBackground(PicoColors.appBackground)
            .presentationCornerRadius(PicoCreamCardStyle.sheetCornerRadius)
        }
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
            await berryStore.loadBalance(for: sessionStore.session)
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

    private var fishCatchSheetDetents: Set<PresentationDetent> {
        let expectedRowCount = max(
            fishStore.currentSessionCatches.count,
            fishStore.isLoadingSessionCatches ? 3 : 0
        )
        let height = max(300, estimatedFishCatchSheetHeight(rowCount: expectedRowCount), ceil(fishCatchSheetHeight))
        return [.height(height)]
    }

    private func estimatedFishCatchSheetHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }

        let rowHeight: CGFloat = 80
        let rowSpacing = CGFloat(max(0, rowCount - 1)) * PicoSpacing.iconTextGap
        let rowsHeight = CGFloat(rowCount) * rowHeight + rowSpacing

        return PicoSpacing.section
            + 25
            + PicoSpacing.standard
            + rowsHeight
            + PicoSpacing.standard
            + 56
            + PicoSpacing.compact
            + PicoSpacing.standard
    }

    private var gridResidents: [VillageResident] {
        Array(villageStore.residents.prefix(36))
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

        if let lobbySession = focusStore.lobbySession {
            startFocusStep = lobbySession.mode == .solo ? .soloConfig : .multiplayerLobby
        } else {
            startFocusStep = .modePicker
        }

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
        await refreshLiveVillageData(
            session: sessionStore.session,
            focusStore: focusStore,
            villageStore: villageStore
        )
        await friendStore.loadFriends(for: sessionStore.session)
        await berryStore.loadBalance(for: sessionStore.session)
    }

    private func villageHeight(for viewportHeight: CGFloat) -> CGFloat {
        max(280, viewportHeight - 54)
    }

    private var villageMapSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > 60,
                      abs(horizontalDistance) > abs(verticalDistance) * 1.25 else {
                    return
                }

                withAnimation(.snappy(duration: 0.22)) {
                    villageMapStyle = horizontalDistance > 0 ? .sandIsland : .originalIsland
                }
            }
    }

    private func viewCompletedSessionFish() {
        guard let resultSession = focusStore.resultSession, resultSession.status == .completed else { return }
        isFishCatchSheetPresented = true
        Task {
            if fishStore.fishCatalog.isEmpty {
                await fishStore.loadFishCatalog(for: sessionStore.session)
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
            if fishStore.fishCatalog.isEmpty {
                await fishStore.loadFishCatalog(for: sessionStore.session)
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
}

private struct FishCatchSuccessSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let catches: [FishCatch]
    let catalog: [FishCatalogItem]
    let isLoading: Bool
    let notice: String?
    @Binding var measuredHeight: CGFloat
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
        VStack(spacing: PicoSpacing.standard) {
            Text("Fish caught")
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

            ZStack {
                FocusCompleteConfettiView(reduceMotion: reduceMotion)
                    .frame(width: 280, height: 112)
                    .allowsHitTesting(false)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                } else if rows.isEmpty {
                    VStack(spacing: PicoSpacing.compact) {
                        Text(notice ?? "No fish found for this session yet.")
                            .font(PicoTypography.body)
                            .foregroundStyle(PicoColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)

                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(PicoSecondaryButtonStyle())
                    }
                    .padding(.horizontal, PicoSpacing.cardPadding)
                } else {
                    VStack(spacing: PicoSpacing.iconTextGap) {
                        ForEach(rows) { row in
                            HStack(spacing: PicoSpacing.standard) {
                                FishCatchIcon(
                                    row: row,
                                    size: 68,
                                    imagePadding: 0,
                                    showsChrome: false
                                )

                                Text(row.label)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(PicoColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)

                                Spacer(minLength: 0)

                                Text(row.rarityLabel)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(row.rarityTextColor)
                                    .padding(.horizontal, PicoSpacing.compact)
                                    .padding(.vertical, 4)
                                    .background(row.rarityBadgeBackground)
                                    .clipShape(Capsule(style: .continuous))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(row.rowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                                    .stroke(row.rowBorder, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .frame(minHeight: 132)

            Button("Done") {
                onDone()
            }
            .buttonStyle(PicoPrimaryButtonStyle())
            .padding(.top, PicoSpacing.compact)
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.top, PicoSpacing.section)
        .padding(.bottom, PicoSpacing.standard)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            let roundedHeight = ceil(height)
            guard abs(measuredHeight - roundedHeight) > 0.5 else { return }
            measuredHeight = roundedHeight
        }
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

    var rowBackground: Color {
        switch rarity {
        case .common:
            PicoColors.softSurface.opacity(0.72)
        case .rare:
            Color(hex: 0xEAF6DE).opacity(0.9)
        case .ultraRare:
            Color(hex: 0xFCE8CC).opacity(0.92)
        }
    }

    var rowBorder: Color {
        switch rarity {
        case .common:
            PicoColors.border.opacity(0.42)
        case .rare:
            PicoColors.primary.opacity(0.34)
        case .ultraRare:
            PicoColors.highlightBorder.opacity(0.36)
        }
    }

    var valueColor: Color {
        switch rarity {
        case .common:
            PicoColors.textPrimary
        case .rare:
            PicoColors.primary
        case .ultraRare:
            PicoColors.highlightBorder
        }
    }

    var rarityTextColor: Color {
        switch rarity {
        case .common:
            PicoColors.textSecondary
        case .rare:
            PicoColors.primary
        case .ultraRare:
            PicoColors.highlightBorder
        }
    }

    var rarityBadgeBackground: Color {
        switch rarity {
        case .common:
            PicoColors.textSecondary.opacity(0.12)
        case .rare:
            PicoColors.primary.opacity(0.14)
        case .ultraRare:
            PicoColors.highlight.opacity(0.18)
        }
    }

    var border: Color {
        switch rarity {
        case .common:
            Color(hex: 0x111111)
        case .rare:
            PicoColors.border
        case .ultraRare:
            PicoColors.error.opacity(0.68)
        }
    }

    var iconBackground: Color {
        switch rarity {
        case .common:
            Color(hex: 0xEEF2E7)
        case .rare:
            Color(hex: 0x7B8F62).opacity(0.28)
        case .ultraRare:
            Color(hex: 0xFBE7EA)
        }
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
                        .fill(row.iconBackground)
                }
            }
            .overlay {
                if showsChrome {
                    RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                        .stroke(row.border.opacity(0.34), lineWidth: 1)
                }
            }
            .shadow(color: showsChrome ? row.border.opacity(0.16) : .clear, radius: 4, x: 0, y: 2)
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
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(row.valueColor)
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

    var body: some View {
        PicoScreenTopBar(
            title: "",
            leading: {
                VStack(alignment: .leading, spacing: 2) {
                    if showsMenuButton {
                        PicoNavigationMenuButton(action: openNavigation)
                    } else {
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                }
            },
            trailing: {
                HomeTopBarStats(
                    berryCount: berryCount,
                    completionStreak: completionStreak
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(formattedBerryCount(berryCount)), \(completionStreak) day streak"))
            }
        )
    }
}

private struct HomeTopBarStats: View {
    let berryCount: Int
    let completionStreak: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: PicoSpacing.tiny) {
                BerryBalanceIcon(size: 18)

                Text("\(berryCount)")
                    .font(PicoTypography.body.weight(.bold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .monospacedDigit()
            }

            HStack(spacing: PicoSpacing.tiny) {
                PicoIcon(.fireSolid, size: 12)
                    .foregroundStyle(PicoColors.streakAccent)

                Text("\(completionStreak)")
                    .font(PicoTypography.caption.weight(.bold))
                    .foregroundStyle(PicoColors.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(width: 76, height: 44, alignment: .topTrailing)
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
                .font(.system(size: 24, weight: .bold, design: .rounded))
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
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore
    @State private var claimedReward: BondRewardClaimCelebration?

    private var bonds: [VillageResident] {
        villageStore.residents
            .filter { $0.completedPairSessions > 0 }
            .sorted {
                if $0.completedPairSessions != $1.completedPairSessions {
                    return $0.completedPairSessions > $1.completedPairSessions
                }

                return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: PicoSpacing.compact) {
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
            }
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
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                ProgressView()
                    .tint(PicoColors.primary)
            }
            .padding(PicoSpacing.standard)
            .picoCreamCard()
        } else if bonds.isEmpty {
            VStack(spacing: PicoSpacing.compact) {
                PicoIcon(.sparklesRegular, size: 28)
                    .foregroundStyle(PicoColors.primary)

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
            .picoCreamCard()
        } else {
            VStack(alignment: .leading, spacing: PicoSpacing.compact) {
                Text("Complete sessions together to earn XP.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("1 group session = 1 bond XP.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BondsListCard(
                    residents: bonds,
                    ownerID: currentUserID,
                    onClaim: claimReward
                )
            }
        }
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

        bondRewardClaimStore.markClaimed(
            level: reward.level,
            ownerID: currentUserID,
            residentID: resident.id
        )

        claimedReward = BondRewardClaimCelebration(
            reward: reward,
            currentProfile: sessionStore.profile,
            resident: resident
        )
    }
}

private struct BondsListCard: View {
    let residents: [VillageResident]
    let ownerID: UUID?
    let onClaim: (VillageResident) -> Void

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            ForEach(residents) { resident in
                BondRowView(
                    resident: resident,
                    ownerID: ownerID,
                    onClaim: onClaim
                )
            }
        }
    }
}

private struct BondRowView: View {
    @EnvironmentObject private var bondRewardClaimStore: BondRewardClaimStore

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
        min(claimedLevel, resident.bondLevel)
    }

    private var scarfProgress: BondScarfProgress {
        BondScarfProgress(xp: xp, claimableReward: pendingReward)
    }

    private var cardBackground: Color {
        pendingReward == nil
            ? PicoCreamCardStyle.background
            : PicoColors.highlight.opacity(0.18)
    }

    private var cardBorder: Color {
        pendingReward == nil
            ? PicoCreamCardStyle.border
            : PicoColors.highlight.opacity(0.42)
    }

    var body: some View {
        Group {
            if pendingReward != nil {
                Button {
                    onClaim(resident)
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
        .picoCreamCard(
            padding: PicoSpacing.cardPadding,
            background: cardBackground,
            border: cardBorder
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(resident.profile.displayName), bond level \(resident.bondLevel), \(xp) XP, \(scarfProgress.accessibilitySummary)")
        )
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
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)

                    Text("@\(resident.profile.username)")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Level \(resident.bondLevel)")
                        .font(PicoTypography.caption.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)
                        .lineLimit(1)

                    Text("\(xp) xp")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                }
            }

            BondScarfProgressBar(progress: scarfProgress)
                .padding(.leading, 56 + PicoSpacing.standard)
                .accessibilityHidden(true)

            if let progressLabel = scarfProgress.caption {
                Text(progressLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 56 + PicoSpacing.standard)
            }
        }
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
        if claimableReward != nil {
            return "Tap to claim reward"
        }

        guard let targetMilestone else {
            return "All rewards unlocked"
        }

        let remainingXP = max(targetMilestone.requiredXP - xp, 0)
        return "\(remainingXP) xp to next scarf"
    }

    var accessibilitySummary: String {
        if let claimableReward {
            return "level \(claimableReward.level) reward ready to claim"
        }

        guard let targetMilestone else {
            return "top scarf unlocked"
        }

        return "\(xp) of \(targetMilestone.requiredXP) XP toward \(targetMilestone.name) scarf"
    }
}

private struct BondScarfMilestone {
    let level: Int
    let name: String
    let requiredXP: Int

    static let all: [BondScarfMilestone] = [
        BondScarfMilestone(level: 2, name: "green", requiredXP: 3),
        BondScarfMilestone(level: 3, name: "blue", requiredXP: 6),
        BondScarfMilestone(level: 4, name: "orange", requiredXP: 9),
        BondScarfMilestone(level: 5, name: "orange", requiredXP: 12)
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

    static func nextClaimable(earnedLevel: Int, claimedLevel: Int) -> BondScarfReward? {
        BondScarfMilestone.all
            .first { $0.level <= earnedLevel && $0.level > claimedLevel }
            .map { BondScarfReward(level: $0.level, name: $0.name) }
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
                    .font(PicoTypography.body.weight(.semibold))
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
                .font(PicoTypography.caption.weight(.semibold))
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

private struct HomeFocusBottomBar: View {
    let mode: StartFocusCTA.Mode
    let isLoadingBalance: Bool
    let balanceNotice: String?
    let incomingInviteCount: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            if isLoadingBalance || balanceNotice != nil {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
    }
}

private struct StartFocusCTA: View {
    enum Mode {
        case startFocus
        case viewFish
    }

    let mode: Mode
    let incomingInviteCount: Int
    let isLoading: Bool
    let action: () -> Void

    private var title: String {
        switch mode {
        case .startFocus:
            "Start Focus"
        case .viewFish:
            "Fish caught"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: PicoSpacing.compact) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if mode == .viewFish {
                        Image(systemName: "fish")
                            .font(.system(size: 22, weight: .semibold))
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
        .buttonStyle(.plain)
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
        Capsule(style: .continuous)
            .fill(
                mode == .viewFish
                    ? Color(hex: 0x54B8FF)
                    : PicoColors.primary
            )
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
            PicoColors.primary.opacity(0.24)
        case .viewFish:
            Color(hex: 0x54B8FF).opacity(0.22)
        }
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
                icon: .clockRegular,
                title: "Solo"
            ) {
                step = .soloConfig
            }

            FocusModeRow(
                icon: .usersRegular,
                title: "With friends"
            ) {
                step = .multiplayerConfig
            }

            if !focusStore.incomingInvites.isEmpty {
                FocusModeRow(
                    icon: .envelopeRegular,
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

    let invite: FocusSessionInvite
    private let avatarColumnSize: CGFloat = 42
    private let avatarSize: CGFloat = 38

    var body: some View {
        inviteCardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
    }

    private var inviteCardContent: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(alignment: .center, spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(
                    config: invite.host.avatarConfig,
                    size: avatarSize,
                    scarf: villageStore.scarf(for: invite.host.userID)
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
}

private struct FocusDurationBadge: View {
    let seconds: Int

    var body: some View {
        HStack(spacing: 6) {
            PicoIcon(.clockRegular, size: 13)
                .foregroundStyle(PicoColors.primary)

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
}

private struct FocusModeRow: View {
    let icon: PicoIconAsset
    let title: String
    var isHighlighted = false
    let action: () -> Void
    private let iconSize: CGFloat = 28
    private let iconFrameSize: CGFloat = 36
    private let chevronSize: CGFloat = 17

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.standard) {
                PicoIcon(icon, size: iconSize)
                    .foregroundStyle(iconColor)
                    .frame(width: iconFrameSize, height: iconFrameSize)

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(title)
                        .font(PicoTypography.body.weight(.bold))
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

private struct FocusSheetActionLabel: View {
    let title: String
    let icon: PicoIconAsset
    var placement: FocusSheetActionIconPlacement = .leading
    var showsProgress = false
    var progressTint: Color = PicoColors.textPrimary

    private let iconSize: CGFloat = 22
    private let iconFrameSize: CGFloat = 28

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

    private var iconView: some View {
        PicoIcon(icon, size: iconSize)
            .frame(width: iconFrameSize, height: iconFrameSize)
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
                .font(.system(size: 40, weight: .bold, design: .rounded))
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
                    Text("Start Solo")
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
                    icon: .userPlusRegular
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

            Button {
                Task {
                    await sendInvites()
                }
            } label: {
                FocusSheetActionLabel(
                    title: buttonTitle,
                    icon: .paperAirplaneRegular,
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
            selectedFriendIDs.insert(friend.userID)
        }
    }

    private func sendInvites() async {
        let selectedFriends = friendStore.friends.filter { selectedFriendIDs.contains($0.userID) }
        guard !selectedFriends.isEmpty else { return }

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
    @EnvironmentObject private var villageStore: VillageStore

    let friend: UserProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(
                    config: friend.avatarConfig,
                    size: 40,
                    scarf: villageStore.scarf(for: friend.userID)
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
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
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
                FocusDurationBadge(seconds: session.durationSeconds)
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
                                PicoIcon(.userPlusRegular, size: 17)
                                    .frame(width: 22, height: 22)
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

                HStack(spacing: 5) {
                    PicoIcon(.infoRegular, size: 13)

                    Text("Bond rewards unlock when both players finish")
                        .font(PicoTypography.caption)
                }
                .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
	
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

                    Button("Leave Lobby", role: .destructive) {
                        Task {
                            await focusStore.leaveCurrentMultiplayerSession(for: sessionStore.session)
                        }
                    }
                    .buttonStyle(PicoDestructiveButtonStyle())
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
                .font(.system(size: 44, weight: .bold, design: .rounded))
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
        session.mode == .multiplayer && !focusStore.isCurrentUserHost(sessionStore.session)
    }

    private var currentVillageResidentIDs: Set<UUID> {
        Set(villageStore.residents.map(\.profile.userID))
    }
}

private struct FocusCompleteOverlay: View {
    let session: FocusSession
    let done: () -> Void

    var body: some View {
        ZStack {
            PicoColors.appBackground
                .ignoresSafeArea()

            FocusCompleteCard(session: session, done: done)
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
    let done: () -> Void

    private var avatarConfig: AvatarConfig {
        sessionStore.profile?.avatarConfig ?? AvatarCatalog.defaultConfig
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(resultTitle)
                .font(PicoTypography.body.weight(.bold))
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

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

            if session.status != .completed {
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
            } else {
                Button("Done") {
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
        case .interrupted:
            return "Session Interrupted"
        case .cancelled:
            return "Session Cancelled"
        case .lobby, .launched, .live:
            return "Session"
        }
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
        return focusStore.completionContext
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
        if let groupCompletionContext {
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
    @EnvironmentObject private var villageStore: VillageStore

    let member: FocusSessionMember
    let isNewPeer: Bool

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            ZStack(alignment: .topTrailing) {
                UserAvatar(
                    config: member.profile.avatarConfig,
                    maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
                    usesHappyIdle: true,
                    scarf: villageStore.scarf(for: member.userID)
                )
                .frame(
                    width: FocusCompleteAvatarLayout.avatarWidth,
                    height: FocusCompleteAvatarLayout.avatarHeight
                )

                if isNewPeer {
                    Text("New")
                        .font(.caption2.weight(.bold))
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
    @EnvironmentObject private var villageStore: VillageStore

    let member: FocusSessionMember

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            AvatarBadgeView(
                config: member.profile.avatarConfig,
                size: 40,
                scarf: villageStore.scarf(for: member.userID)
            )

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                HStack(spacing: PicoSpacing.tiny) {
                    Text(member.profile.displayName)
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)

                    if member.role == .host {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
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
    @EnvironmentObject private var fishStore: FishStore

    private var catalogFish: [FishingCatalogFish] {
        fishStore.fishCatalog
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap(FishingCatalogFish.init(catalogItem:))
    }

    private var collectionCounts: [FishID: Int] {
        Dictionary(
            uniqueKeysWithValues: fishStore.collectionCounts.map { count in
                (count.seaCritterID, count.count)
            }
        )
    }

    private var isLoadingCollectionData: Bool {
        fishStore.isLoadingFishCatalog || fishStore.isLoadingCollectionCounts
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PicoSpacing.section) {
                if let notice = fishStore.notice {
                    ProfileNoticeCard(text: notice)
                }

                ForEach(FishingTier.allCases) { tier in
                    FishingTierSection(
                        tier: tier,
                        fish: catalogFish.filter { $0.tier == tier },
                        counts: collectionCounts,
                        isLoading: isLoadingCollectionData
                    )
                }
            }
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.vertical, PicoSpacing.section)
            .padding(.bottom, PicoSpacing.largeSection)
        }
        .picoScreenBackground()
        .task {
            await loadFishingData()
        }
        .refreshable {
            await loadFishingData()
        }
    }

    private func loadFishingData() async {
        if fishStore.fishCatalog.isEmpty {
            await fishStore.loadFishCatalog(for: sessionStore.session)
        }

        await fishStore.loadCollectionCounts(for: sessionStore.session)
    }
}

private enum FishingTier: String, CaseIterable, Identifiable {
    case common
    case rare
    case ultraRare = "ultra_rare"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common:
            "Common"
        case .rare:
            "Rare"
        case .ultraRare:
            "Ultra Rare"
        }
    }

    var accentColor: Color {
        switch self {
        case .common:
            PicoColors.primary
        case .rare:
            PicoColors.highlightBorder
        case .ultraRare:
            PicoColors.secondaryAccent
        }
    }

    var cardBackground: Color {
        switch self {
        case .common:
            Color(hex: 0xF3FAEA)
        case .rare:
            Color(hex: 0xFFF7E8)
        case .ultraRare:
            Color(hex: 0xF2F0FF)
        }
    }

    var badgeBackground: Color {
        accentColor.opacity(0.14)
    }

    var sectionIconName: String {
        switch self {
        case .common:
            "fish"
        case .rare:
            "star.fill"
        case .ultraRare:
            "crown.fill"
        }
    }

    init?(rarity: FishRarity) {
        switch rarity {
        case .common:
            self = .common
        case .rare:
            self = .rare
        case .ultraRare:
            self = .ultraRare
        }
    }
}

private func fishImageResourceCandidates(named assetName: String) -> [String] {
    [
        "Icons/fish/\(assetName)",
        "Icons/fish/\(assetName).png",
        "fish/\(assetName)",
        "fish/\(assetName).png",
        assetName,
        "\(assetName).png"
    ]
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

    init?(
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

    init?(catalogItem: FishCatalogItem) {
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

private struct FishingTierSection: View {
    let tier: FishingTier
    let fish: [FishingCatalogFish]
    let counts: [FishType: Int]
    let isLoading: Bool

    private var unlockedCount: Int {
        fish.filter { counts[$0.seaCritterID, default: 0] > 0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            FishingSectionHeader(
                iconName: tier.sectionIconName,
                title: tier.title,
                countText: "\(unlockedCount) / \(fish.count)",
                countIcon: "archivebox.fill",
                accentColor: tier.accentColor,
                isLoading: isLoading
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 94), spacing: PicoSpacing.iconTextGap)],
                spacing: PicoSpacing.iconTextGap
            ) {
                ForEach(fish) { catalogFish in
                    FishingCollectionTile(
                        fish: catalogFish,
                        count: count(for: catalogFish)
                    )
                }
            }
        }
        .picoCreamCard(
            cornerRadius: PicoRadius.large,
            showsShadow: false,
            padding: PicoCreamCardStyle.contentPadding,
            background: tier.cardBackground,
            border: tier.accentColor.opacity(0.3)
        )
    }

    private func count(for catalogFish: FishingCatalogFish) -> Int {
        counts[catalogFish.seaCritterID, default: 0]
    }
}

private struct FishingCollectionTile: View {
    let fish: FishingCatalogFish
    let count: Int

    private var isUnlocked: Bool {
        count > 0
    }

    var body: some View {
        VStack(spacing: PicoSpacing.iconTextGap) {
            FishingCatalogIcon(
                fish: fish,
                isUnlocked: isUnlocked,
                size: 90
            )
            .frame(height: 94)

            VStack(spacing: 6) {
                Text(isUnlocked ? fish.displayName : "???")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.68)

                FishingRarityBadge(
                    rarityName: fish.tier.title.lowercased(),
                    textColor: fish.tier.accentColor,
                    background: fish.tier.badgeBackground
                )

                if isUnlocked {
                    Text("x\(count)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PicoColors.textPrimary)
                        .monospacedDigit()
                } else {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PicoColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 214)
        .padding(.horizontal, PicoSpacing.compact)
        .padding(.vertical, PicoSpacing.standard)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                .stroke(tileBorder, lineWidth: 1)
        )
    }

    private var tileBackground: Color {
        if !isUnlocked {
            return PicoColors.softSurface.opacity(0.72)
        }

        return PicoColors.surface.opacity(0.56)
    }

    private var tileBorder: Color {
        if !isUnlocked {
            return PicoColors.border.opacity(0.7)
        }

        return fish.tier.accentColor.opacity(0.46)
    }
}

private struct FishingSectionHeader: View {
    let iconName: String
    let title: String
    let countText: String
    let countIcon: String?
    var accentColor: Color = PicoColors.textSecondary
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PicoSpacing.iconTextGap) {
            Image(systemName: iconName)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 36, alignment: .top)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PicoTypography.sectionTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .tint(PicoColors.primary)
                    .frame(height: 36)
            } else {
                HStack(spacing: 6) {
                    if let countIcon {
                        Image(systemName: countIcon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(accentColor)
                    }

                    Text(countText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PicoColors.textPrimary)
                        .monospacedDigit()
                }
                .padding(.horizontal, PicoSpacing.iconTextGap)
                .padding(.vertical, 8)
                .background(PicoColors.softSurface.opacity(0.76))
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PicoColors.border.opacity(0.84), lineWidth: 1)
                )
            }
        }
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
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(isUnlocked ? fish.tier.accentColor : Color.black.opacity(0.94))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fishImage: UIImage? {
        fish.imageResourceCandidates.lazy.compactMap { UIImage(named: $0) }.first
    }
}

private struct FishingRarityBadge: View {
    let rarityName: String
    let textColor: Color
    let background: Color

    var body: some View {
        Text(rarityName)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, PicoSpacing.compact)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule(style: .continuous))
    }
}

private struct StorePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var berryStore: BerryStore
    @EnvironmentObject private var fishStore: FishStore
    @State private var selectedMode: StoreMode = .buy

    private var purchasableHats: [AvatarHat] {
        AvatarHat.allCases.filter { $0 != .none }
    }

    private var fishGroups: [StoreFishGroup] {
        StoreFishGroup.groups(
            from: fishStore.inventory,
            catalog: fishStore.fishCatalog,
            inventoryCounts: fishStore.inventoryCounts
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                berryBalanceCard

                if let notice = berryStore.notice {
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
                        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                            StoreHatsSectionHeader()

                            VStack(spacing: PicoSpacing.compact) {
                                ForEach(purchasableHats) { hat in
                                    StoreHatRow(
                                        hat: hat,
                                        berryBalance: berryStore.balance.berries,
                                        isOwned: hat.isOwned(in: sessionStore.ownedHats),
                                        isPurchasing: berryStore.purchasingHat == hat,
                                        isPurchaseDisabled: berryStore.purchasingHat != nil || berryStore.isLoadingBalance || sessionStore.session == nil
                                    ) {
                                        purchase(hat)
                                    }
                                }
                            }
                        }
                        .picoCreamCard(
                            padding: PicoCreamCardStyle.contentPadding
                        )
                    case .sell:
                        StoreFishSection(
                            groups: fishGroups,
                            isLoading: fishStore.isLoadingInventory,
                            isSelling: fishStore.isSellingFish,
                            sellGroup: sellFishGroup
                        )
                    }
                }
            }
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.vertical, PicoSpacing.section)
            .padding(.bottom, PicoSpacing.largeSection)
        }
        .picoScreenBackground()
        .task {
            await sessionStore.loadProfileIfNeeded()
            await berryStore.loadBalance(for: sessionStore.session)
            if fishStore.fishCatalog.isEmpty {
                await fishStore.loadFishCatalog(for: sessionStore.session)
            }
            await fishStore.loadInventoryCounts(for: sessionStore.session)
            await fishStore.loadInventory(for: sessionStore.session)
        }
    }

    private var berryBalanceCard: some View {
        HStack(alignment: .center, spacing: PicoSpacing.standard) {
            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text("Berry balance")
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
            padding: PicoCreamCardStyle.contentPadding
        )
    }

    private func purchase(_ hat: AvatarHat) {
        Task {
            guard let result = await berryStore.purchaseAvatarHat(hat, for: sessionStore.session) else { return }
            sessionStore.applyOwnedHats(result.ownedHats)
        }
    }

    private func sellFishGroup(_ group: StoreFishGroup) {
        guard let fishCatch = group.catches.first else { return }
        sellFish([fishCatch])
    }

    private func sellFish(_ catches: [FishCatch]) {
        let catchIDs = catches.map(\.id)
        Task {
            guard let result = await fishStore.sellFish(catchIDs: catchIDs, for: sessionStore.session) else { return }
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
    let inventoryCount: Int?
    let catches: [FishCatch]

    var fishType: FishType {
        seaCritterID
    }

    var count: Int {
        inventoryCount ?? catches.count
    }

    var totalValue: Int {
        catches.reduce(0) { $0 + $1.sellValue }
    }

    var imageResourceCandidates: [String] {
        fishImageResourceCandidates(named: assetName)
    }

    var rowBackground: Color {
        switch rarity {
        case .common:
            PicoColors.softSurface.opacity(0.72)
        case .rare:
            Color(hex: 0xEAF6DE).opacity(0.9)
        case .ultraRare:
            Color(hex: 0xFCE8CC).opacity(0.92)
        }
    }

    var rowBorder: Color {
        switch rarity {
        case .common:
            PicoColors.border.opacity(0.42)
        case .rare:
            PicoColors.primary.opacity(0.34)
        case .ultraRare:
            PicoColors.highlightBorder.opacity(0.36)
        }
    }

    var iconBorder: Color {
        switch rarity {
        case .common:
            Color(hex: 0x111111)
        case .rare:
            PicoColors.border
        case .ultraRare:
            PicoColors.error.opacity(0.68)
        }
    }

    static func groups(
        from catches: [FishCatch],
        catalog: [FishCatalogItem],
        inventoryCounts: [FishCount]
    ) -> [StoreFishGroup] {
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let inventoryCountByID = Dictionary(uniqueKeysWithValues: inventoryCounts.map { ($0.seaCritterID, $0) })

        return Dictionary(grouping: catches, by: \.seaCritterID)
            .map { seaCritterID, catches in
                let catalogItem = catalogByID[seaCritterID]
                let countItem = inventoryCountByID[seaCritterID]
                let firstCatch = catches.first

                return StoreFishGroup(
                    seaCritterID: seaCritterID,
                    displayName: catalogItem?.displayName ?? countItem?.displayName ?? seaCritterID.displayName,
                    rarity: catalogItem?.rarity ?? countItem?.rarity ?? firstCatch?.rarity ?? .common,
                    assetName: catalogItem?.assetName ?? countItem?.assetName ?? seaCritterID.assetName,
                    sortOrder: catalogItem?.sortOrder ?? countItem?.sortOrder ?? Int.max,
                    unitValue: catalogItem?.sellValue ?? countItem?.sellValue ?? firstCatch?.sellValue ?? seaCritterID.sellValue,
                    inventoryCount: countItem?.count,
                    catches: catches
                )
            }
            .sorted { lhs, rhs in
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
    let sellGroup: (StoreFishGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                Image(systemName: "fish")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PicoColors.textSecondary)
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
                            sell: {
                                sellGroup(group)
                            }
                        )
                    }
                }
            }
        }
        .picoCreamCard(
            padding: PicoCreamCardStyle.contentPadding
        )
    }
}

private struct StoreFishGroupRow: View {
    let group: StoreFishGroup
    let isSelling: Bool
    let sell: () -> Void

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            fishIcon

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text(group.displayName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                BerryAmountLabel(
                    count: group.unitValue,
                    font: PicoTypography.caption.weight(.bold),
                    iconSize: 15,
                    textColor: PicoColors.textPrimary
                )
            }

            Spacer(minLength: PicoSpacing.compact)

            VStack(alignment: .trailing, spacing: PicoSpacing.compact) {
                Button("Sell") {
                    sell()
                }
                .buttonStyle(StoreBuyButtonStyle())
                .disabled(isSelling)
                .accessibilityLabel(Text("Sell one \(group.displayName)"))
            }
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
        ZStack {
            StoreFishIcon(
                group: group,
                size: 68,
                imagePadding: 0
            )

            Text("x \(group.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(group.iconBorder)
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

private struct StoreHatRow: View {
    let hat: AvatarHat
    let berryBalance: Int
    let isOwned: Bool
    let isPurchasing: Bool
    let isPurchaseDisabled: Bool
    let purchase: () -> Void

    private var missingBerries: Int {
        max(0, hat.berryCost - berryBalance)
    }

    private var canPurchase: Bool {
        !isOwned && missingBerries == 0 && !isPurchaseDisabled
    }

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            AvatarBadgeView(config: AvatarCatalog.defaultConfig.withHat(hat), size: 58)

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text(hat.name)
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)

                BerryAmountLabel(
                    count: hat.berryCost,
                    font: PicoTypography.caption,
                    iconSize: 15,
                    textColor: PicoColors.textSecondary
                )
            }

            Spacer(minLength: PicoSpacing.compact)

            purchaseControl
                .frame(width: 86, alignment: .trailing)
        }
        .padding(PicoSpacing.compact)
        .background(PicoColors.softSurface.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var purchaseControl: some View {
        if isOwned {
            HStack(spacing: PicoSpacing.tiny) {
                Text("✓")
                    .font(PicoTypography.caption.weight(.bold))

                Text("Owned")
                    .font(PicoTypography.caption.weight(.semibold))
            }
            .foregroundStyle(PicoColors.primary.opacity(0.78))
            .frame(height: 34, alignment: .trailing)
        } else {
            Button {
                purchase()
            } label: {
                HStack(spacing: PicoSpacing.tiny) {
                    Text("Buy")

                    if isPurchasing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(canPurchase ? PicoColors.textOnPrimary : PicoColors.textSecondary)
                    }
                }
            }
            .buttonStyle(StoreBuyButtonStyle())
            .disabled(!canPurchase)
        }
    }
}

private struct StoreHatsSectionHeader: View {
    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            if let image = UIImage(named: "Hat_Icon") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "hat.widebrim")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(width: 24, height: 24)
            }

            Text("Hats")
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
        }
    }
}

private struct StoreBuyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.body.weight(.bold))
            .foregroundStyle(isEnabled ? PicoColors.textOnPrimary : PicoColors.primary.opacity(0.38))
            .frame(width: 68, height: 38)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(isEnabled ? PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1) : PicoColors.softSurface.opacity(0.72))
            )
            .shadow(
                color: isEnabled ? PicoColors.primary.opacity(0.18) : .clear,
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

private struct ProfilePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @State private var displayName = ""
    @State private var draftDisplayName = ""
    @State private var avatarConfig = AvatarCatalog.defaultConfig
    @State private var isNameEditorPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: PicoSpacing.standard) {
                profileContent

                if sessionStore.profile != nil {
                    ProfileAvatarOutfitCard(
                        avatarConfig: avatarConfig,
                        canCycleHats: ownedHats.count >= 2,
                        previousHat: selectPreviousHat,
                        nextHat: selectNextHat
                    )

                    ProfileHatCollectionCard(
                        selection: $avatarConfig,
                        ownedHats: sessionStore.ownedHats
                    )

                    saveProfileButton
                }

                if let profileNotice = sessionStore.profileNotice {
                    ProfileNoticeCard(text: profileNotice)
                }

                ProfileSignOutBar {
                    sessionStore.signOut()
                }
                .padding(.top, PicoSpacing.section)
            }
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.vertical, PicoSpacing.section)
            .padding(.bottom, PicoSpacing.largeSection)
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
                .presentationDetents([.height(280)])
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
                ProfileCardView(profile: profile, displayName: displayName, avatarConfig: avatarConfig)
            }
            .buttonStyle(.plain)
        } else if sessionStore.isProfileLoading {
            ProgressView("Loading profile")
                .font(PicoTypography.caption)
                .tint(PicoColors.primary)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .picoCreamCard(
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

    private var saveProfileButton: some View {
        Button {
            Task {
                await sessionStore.updateProfile(
                    displayName: displayName,
                    avatarConfig: avatarConfig
                )
            }
        } label: {
            HStack(spacing: PicoSpacing.compact) {
                Text("Save Profile")

                if sessionStore.isProfileSaving {
                    ProgressView()
                        .tint(PicoColors.textOnPrimary)
                }
            }
        }
        .buttonStyle(PicoPrimaryButtonStyle())
        .disabled(!canSave || sessionStore.isProfileSaving)
        .opacity((canSave && !sessionStore.isProfileSaving) ? 1 : 0.62)
    }

    private var canSave: Bool {
        guard let profile = sessionStore.profile else { return false }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidDisplayName = (1...40).contains(normalizedDisplayName.count)
        let hasOwnedHat = avatarConfig.selectedHat.isOwned(in: sessionStore.ownedHats)
        let hasChanges = normalizedDisplayName != profile.displayName || avatarConfig != profile.avatarConfig
        return hasValidDisplayName && hasOwnedHat && hasChanges
    }

    private var ownedHats: [AvatarHat] {
        AvatarHat.allCases.filter { $0.isOwned(in: sessionStore.ownedHats) }
    }

    private func syncEditableProfile() {
        guard let profile = sessionStore.profile else { return }
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
        let hats = ownedHats
        guard hats.count >= 2 else { return }

        guard let currentIndex = hats.firstIndex(of: avatarConfig.selectedHat) else {
            avatarConfig = avatarConfig.withHat(hats[0])
            return
        }

        let nextIndex = (currentIndex + offset + hats.count) % hats.count
        avatarConfig = avatarConfig.withHat(hats[nextIndex])
    }
}

private struct UserAvatar: View {
    let config: AvatarConfig
    var maxSpriteSide: CGFloat = 150
    var usesHappyIdle = false
    var scarf: AvatarScarf? = nil

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: UserAvatarScene(
                    size: proxy.size,
                    hat: config.selectedHat,
                    maxSpriteSide: maxSpriteSide,
                    usesHappyIdle: usesHappyIdle,
                    scarf: scarf
                ),
                options: [.allowsTransparency]
            )
            .id("\(config.selectedHat.id)-\(usesHappyIdle)-\(scarf?.rawValue ?? 0)")
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .accessibilityLabel(Text("User character"))
    }
}

private final class UserAvatarScene: SKScene {
    private static let idleActionKey = "idle"

    private let hat: AvatarHat
    private let maxSpriteSide: CGFloat
    private let usesHappyIdle: Bool
    private let scarf: AvatarScarf?
    private var renderedSize: CGSize = .zero

    init(size: CGSize, hat: AvatarHat, maxSpriteSide: CGFloat, usesHappyIdle: Bool, scarf: AvatarScarf?) {
        self.hat = hat
        self.maxSpriteSide = maxSpriteSide
        self.usesHappyIdle = usesHappyIdle
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

        let frames: AvatarLayeredFrames
        if usesHappyIdle {
            frames = AvatarHappyIdleFrames(hat: hat, scarf: scarf).layeredFrames
        } else {
            frames = AvatarIdleFrames(hat: hat, scarf: scarf).layeredFrames
        }

        let sprite = AvatarLayeredSpriteNode(frames: frames)
        let spriteSide = min(size.width * 0.72, size.height * 0.90, maxSpriteSide)
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

private struct ProfileCardView: View {
    let profile: UserProfile
    let displayName: String
    let avatarConfig: AvatarConfig

    var body: some View {
        HStack(spacing: 14) {
            AvatarBadgeView(config: avatarConfig, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)

                Text("@\(profile.username)")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            PicoIcon(.pencilRegular, size: 17)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(width: 36, height: 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
        .picoCreamCard(
            padding: PicoCreamCardStyle.contentPadding
        )
        .accessibilityLabel(Text("\(displayName), @\(profile.username), edit display name"))
    }
}

private struct ProfileAvatarOutfitCard: View {
    let avatarConfig: AvatarConfig
    let canCycleHats: Bool
    let previousHat: () -> Void
    let nextHat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: PicoSpacing.compact) {
                UserAvatar(config: avatarConfig)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
            }
            .frame(maxWidth: .infinity)
                .padding(.top, PicoSpacing.standard)
                .padding(.horizontal, PicoSpacing.cardPadding)
                .padding(.bottom, PicoSpacing.compact)

            PicoCardDivider(horizontalPadding: 0)

            HStack(spacing: PicoSpacing.standard) {
                Text("Hats")
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                HStack(spacing: PicoSpacing.compact) {
                    hatButton(icon: .chevronLeftRegular, action: previousHat)
                    hatButton(icon: .chevronRightRegular, action: nextHat)
                }
            }
            .padding(.horizontal, PicoCreamCardStyle.contentPadding)
            .padding(.vertical, PicoSpacing.standard)
        }
        .picoCreamCard()
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
}

private struct ProfileHatCollectionCard: View {
    @Binding var selection: AvatarConfig
    let ownedHats: Set<AvatarHat>

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            Text("Hat Collection")
                .font(PicoTypography.body.weight(.semibold))
                .foregroundStyle(PicoColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: PicoSpacing.standard) {
                    ForEach(AvatarHat.allCases) { hat in
                        hatCollectionItem(hat)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .picoCreamCard(
            padding: PicoCreamCardStyle.contentPadding
        )
    }

    private func hatCollectionItem(_ hat: AvatarHat) -> some View {
        let isSelected = selection.selectedHat == hat
        let isOwned = hat.isOwned(in: ownedHats)

        return Button {
            guard isOwned else { return }
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

                            Image(systemName: "lock.fill")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(PicoColors.textOnPrimary)
                        }
                    }
                    .frame(width: 66, height: 66, alignment: .center)

                Text(hat.name)
                    .font(PicoTypography.caption)
                    .foregroundStyle(isSelected ? PicoColors.textPrimary : PicoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if !isOwned {
                    Text("Not owned")
                        .font(.caption2)
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
        .disabled(!isOwned)
        .accessibilityLabel(Text(isOwned ? "\(hat.name) hat" : "\(hat.name) hat, not owned"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .font(PicoTypography.body.weight(.semibold))
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
        } description: {
            Text("Your public profile could not be loaded.")
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
