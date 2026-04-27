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
            .tint(PicoColors.primary)
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
    @StateObject private var scoreStore = ScoreStore()

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
        .environmentObject(scoreStore)
        .task(id: sessionStore.session?.user?.id) {
            await focusStore.restoreSavedState(for: sessionStore.session)
            if sessionStore.session == nil {
                villageStore.clear()
                scoreStore.clear()
                focusStore.updateKnownVillageResidentIDs(nil)
            } else {
                await villageStore.loadResidents(for: sessionStore.session)
                focusStore.updateKnownVillageResidentIDs(currentVillageResidentIDs)
                await scoreStore.loadScore(for: sessionStore.session)
            }
        }
        .onChange(of: focusStore.resultSession) {
            guard focusStore.resultSession?.status == .completed else { return }
            Task {
                await villageStore.loadResidents(for: sessionStore.session)
            }
        }
        .onChange(of: focusStore.completionScoreReceipt) {
            guard let score = focusStore.completionScoreReceipt else { return }
            scoreStore.applyScore(score)
        }
        .onChange(of: villageStore.residents) {
            focusStore.updateKnownVillageResidentIDs(currentVillageResidentIDs)
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task {
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
        isPersistent ? 78 : 286
    }

    private var horizontalPadding: CGFloat {
        isPersistent ? PicoSpacing.iconTextGap : PicoSpacing.standard
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
                    HStack(spacing: PicoSpacing.iconTextGap) {
                        tab.icon
                            .frame(width: 24, height: 24)

                        if !isPersistent {
                            Text(tab.title)
                                .font(PicoTypography.body.weight(.semibold))

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, isPersistent ? PicoSpacing.compact : PicoSpacing.standard)
                    .foregroundStyle(selectedTab == tab ? PicoColors.primary : PicoColors.textPrimary)
                    .frame(maxWidth: isPersistent ? 52 : .infinity)
                    .frame(height: 52)
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
    case bonds
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Village"
        case .bonds:
            "Bonds"
        case .friends:
            "Friends"
        case .settings:
            "Profile"
        }
    }

    @ViewBuilder
    var icon: some View {
        switch self {
        case .home:
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        case .bonds:
            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        case .friends:
            Image(systemName: "person.2")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
        case .settings:
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
    @EnvironmentObject private var scoreStore: ScoreStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var sessionStore: AuthSessionStore
    let showsMenuButton: Bool
    let openNavigation: () -> Void
    @State private var isStartFocusSheetPresented = false
    @State private var startFocusStep = StartFocusSheetStep.modePicker

    var body: some View {
        ZStack {
            ZStack(alignment: .top) {
                ScrollView {
                    GeometryReader { viewport in
                        VillageHeroSection(
                            residents: gridResidents,
                            currentUserProfile: sessionStore.profile,
                            isLoading: villageStore.isLoadingResidents,
                            notice: villageStore.notice,
                            height: max(0, viewport.size.height - PicoSpacing.compact * 2)
                        )
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
                        score: scoreStore.score.score,
                        isLoadingScore: scoreStore.isLoadingScore,
                        scoreNotice: scoreStore.notice,
                        incomingInviteCount: focusStore.incomingInvites.count,
                        action: presentStartFocusSheet
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeTopBar(
                    currentStreak: scoreStore.currentStreak,
                    showsMenuButton: showsMenuButton,
                    openNavigation: openNavigation
                )
            }
            .allowsHitTesting(focusStore.resultSession == nil)

            if let resultSession = focusStore.resultSession {
                FocusCompleteOverlay(session: resultSession)
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
                isPresented: $isStartFocusSheetPresented
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(PicoColors.appBackground)
            .presentationCornerRadius(PicoCreamCardStyle.sheetCornerRadius)
        }
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
            await scoreStore.loadScore(for: sessionStore.session)
        }
        .onChange(of: focusStore.resultSession) {
            guard focusStore.resultSession != nil else { return }
            isStartFocusSheetPresented = false
        }
        .onChange(of: focusStore.activeSession) {
            guard focusStore.activeSession != nil else { return }
            isStartFocusSheetPresented = false
        }
    }

    private var gridResidents: [VillageResident] {
        Array(villageStore.residents.prefix(36))
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

    private func refreshVillagePage() async {
        await villageStore.loadResidents(for: sessionStore.session)
        await focusStore.refresh(for: sessionStore.session)
        await friendStore.loadFriends(for: sessionStore.session)
        await scoreStore.loadScore(for: sessionStore.session)
    }
}

private struct HomeTopBar: View {
    let currentStreak: Int
    let showsMenuButton: Bool
    let openNavigation: () -> Void

    var body: some View {
        PicoScreenTopBar(
            title: "pico",
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
                HStack(spacing: PicoSpacing.tiny) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(PicoColors.streakAccent)

                    Text("\(currentStreak)")
                        .font(PicoTypography.body.weight(.bold))
                        .foregroundStyle(PicoColors.textPrimary)
                }
                .frame(width: 44, height: 44, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(currentStreak) day streak"))
            }
        )
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PicoColors.textPrimary)
                .frame(width: 44, height: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Open navigation"))
    }
}

private struct BondsPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore

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
            await villageStore.loadResidents(for: sessionStore.session)
        }
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
                Image(systemName: "leaf.fill")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
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
            BondsListCard(residents: bonds)
        }
    }
}

private struct BondsListCard: View {
    let residents: [VillageResident]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(residents.enumerated()), id: \.element.id) { index, resident in
                BondRowView(resident: resident)

                if index < residents.count - 1 {
                    PicoCardDivider()
                }
            }
        }
        .picoCreamCard()
    }
}

private struct BondRowView: View {
    let resident: VillageResident

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            AvatarBadgeView(config: resident.profile.avatarConfig, size: 56)

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

                Text("\(resident.completedPairSessions) sessions")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.vertical, PicoSpacing.standard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(resident.profile.displayName), bond level \(resident.bondLevel), \(resident.completedPairSessions) completed sessions")
        )
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
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            VillageView(
                residents: residents,
                currentUserProfile: currentUserProfile
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
                    Image(systemName: "exclamationmark.circle")
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
    let score: Int
    let isLoadingScore: Bool
    let scoreNotice: String?
    let incomingInviteCount: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            CompactProgressStrip(
                score: score,
                isLoading: isLoadingScore,
                notice: scoreNotice
            )

            StartFocusCTA(incomingInviteCount: incomingInviteCount, action: action)
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
    let incomingInviteCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("Start Focus")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                if incomingInviteCount > 0 {
                    Text("\(incomingInviteCount) invite\(incomingInviteCount == 1 ? "" : "s") waiting")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textOnPrimary.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(PicoColors.textOnPrimary)
            .padding(.horizontal, PicoSpacing.section)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(PicoColors.primary)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: PicoColors.primary.opacity(0.24), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactProgressStrip: View {
    let score: Int
    let isLoading: Bool
    let notice: String?

    private var nextHat: AvatarHat? {
        AvatarHat.allCases.first { $0.requiredScore > score }
    }

    private var previousHatRequirement: Int {
        AvatarHat.allCases
            .filter { $0.requiredScore <= score }
            .map(\.requiredScore)
            .max() ?? 0
    }

    private var hatProgressTotal: Double {
        guard let nextHat else { return 1 }
        return Double(max(1, nextHat.requiredScore - previousHatRequirement))
    }

    private var hatProgressValue: Double {
        guard let nextHat else { return 1 }
        let tierProgress = score - previousHatRequirement
        return Double(min(max(0, tierProgress), nextHat.requiredScore - previousHatRequirement))
    }

    private var nextHatProgressLabel: String {
        guard let nextHat else { return "All hats unlocked" }
        return "\(nextHat.name) unlock: \(Int(hatProgressValue))/\(Int(hatProgressTotal))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(nextHatProgressLabel)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: PicoSpacing.compact)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                }
            }

            SegmentedScoreProgressBar(value: hatProgressValue, total: hatProgressTotal)

            if let notice {
                Text(notice)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct SegmentedScoreProgressBar: View {
    let value: Double
    let total: Double

    private let segmentCount = 10

    private var filledSegmentCount: Int {
        guard total > 0 else { return 0 }
        let normalizedValue = min(max(value / total, 0), 1)
        return min(segmentCount, max(0, Int((normalizedValue * Double(segmentCount)).rounded(.down))))
    }

    var body: some View {
        HStack(spacing: PicoSpacing.tiny) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < filledSegmentCount ? PicoColors.primary : PicoColors.softSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(PicoColors.border.opacity(index < filledSegmentCount ? 0 : 1), lineWidth: 1)
                    )
                    .frame(height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(filledSegmentCount) of \(segmentCount) points"))
    }
}

private struct StartFocusSheet: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep
    @Binding var isPresented: Bool
    @State private var multiplayerDurationMinutes = FocusStore.defaultDurationSeconds / 60

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            sheetHeader

            if usesPinnedSheetContent {
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
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PicoColors.appBackground.ignoresSafeArea())
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
                    durationMinutes: .constant(clampedDurationMinutes(from: lobbySession.durationSeconds)),
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
                    durationMinutes: $multiplayerDurationMinutes
                )
            case .multiplayerInviteMore:
                MultiplayerInviteFriendsSheetContent(
                    step: $step,
                    durationMinutes: $multiplayerDurationMinutes,
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
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
	        VStack(spacing: 0) {
	            Spacer(minLength: 0)
	
	            VStack(spacing: PicoSpacing.iconTextGap) {
	                FocusModeRow(
	                    icon: "timer",
	                    title: "Solo"
	                ) {
	                    step = .soloConfig
	                }
	
	                FocusModeRow(
	                    icon: "person.2",
	                    title: "With friends"
	                ) {
	                    step = .multiplayerConfig
	                }

	                if !focusStore.incomingInvites.isEmpty {
	                    FocusModeRow(
	                        icon: "envelope",
	                        title: "Invites",
	                        isHighlighted: true
	                    ) {
	                        step = .invites
	                    }
	                }
	            }
	            .frame(maxWidth: .infinity)
	
	            Spacer(minLength: 0)
	        }
	        .frame(maxWidth: .infinity, minHeight: 260)
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
                AvatarBadgeView(config: invite.host.avatarConfig, size: avatarSize)
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
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
    let icon: String
    let title: String
    var isHighlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.iconTextGap) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(title)
                        .font(PicoTypography.body.weight(.bold))
                        .foregroundStyle(titleColor)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(chevronColor)
            }
            .padding(PicoCreamCardStyle.sheetCardPadding)
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

private struct FocusDurationSlider: View {
    @Binding var durationMinutes: Int
    let isDisabled: Bool

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(durationMinutes) },
            set: { durationMinutes = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: PicoSpacing.standard) {
            Text(homeFormattedDuration(durationMinutes * 60))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PicoColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            PicoRangeSlider(
                value: sliderValue,
                bounds: 1...120,
                step: 1,
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
        .accessibilityValue(Text(homeFormattedDuration(Int(value.rounded()) * 60)))
        .accessibilityAdjustableAction { direction in
            guard !isDisabled else { return }
            switch direction {
            case .increment:
                value = min(bounds.upperBound, value + step)
            case .decrement:
                value = max(bounds.lowerBound, value - step)
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
        let steppedValue = (rawValue / step).rounded() * step
        value = min(max(steppedValue, bounds.lowerBound), bounds.upperBound)
    }
}

private struct SoloFocusConfigSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @State private var durationMinutes = FocusStore.defaultDurationSeconds / 60

    let session: FocusSession?

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: PicoSpacing.standard) {
                Text("Duration")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textPrimary)

                FocusDurationSlider(durationMinutes: $durationMinutes, isDisabled: isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.sheetCardPadding,
                border: .clear
            )

            Spacer(minLength: 0)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            durationMinutes = clampedDurationMinutes(from: session?.durationSeconds ?? FocusStore.defaultDurationSeconds)
        }
        .onChange(of: session?.durationSeconds) {
            durationMinutes = clampedDurationMinutes(from: session?.durationSeconds ?? FocusStore.defaultDurationSeconds)
        }
    }

    private var isBusy: Bool {
        focusStore.isCreating || focusStore.isUpdatingConfig || focusStore.isStarting
    }

    private func startSolo() async {
        if focusStore.lobbySession?.mode != .solo {
            await focusStore.createLobby(mode: .solo, for: sessionStore.session)
        }

        guard let lobbySession = focusStore.lobbySession, lobbySession.mode == .solo else { return }

        let durationSeconds = durationMinutes * 60
        if lobbySession.durationSeconds != durationSeconds {
            await focusStore.updateLobbyDuration(durationSeconds, for: sessionStore.session)
        }

        await focusStore.startLobbySession(for: sessionStore.session)
    }
}

private struct MultiplayerDurationSheetContent: View {
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep
    @Binding var durationMinutes: Int

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: PicoSpacing.standard) {
                Text("Duration")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textPrimary)

                FocusDurationSlider(durationMinutes: $durationMinutes, isDisabled: focusStore.hasPendingResultSync)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .picoCreamCard(
                showsShadow: false,
                padding: PicoCreamCardStyle.sheetCardPadding,
                border: .clear
            )

            Spacer(minLength: 0)

            Button {
                step = .multiplayerInviteMore
            } label: {
                Label("Invite friends", systemImage: "person.badge.plus")
            }
            .buttonStyle(PicoSecondaryButtonStyle())
            .disabled(focusStore.hasPendingResultSync)
            .opacity(focusStore.hasPendingResultSync ? 0.62 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MultiplayerInviteFriendsSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var step: StartFocusSheetStep
    @Binding var durationMinutes: Int
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
                HStack {
                    Label(buttonTitle, systemImage: "paperplane.fill")
                    if isBusy {
                        ProgressView()
                            .tint(PicoColors.textPrimary)
                    }
                }
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
                durationSeconds: durationMinutes * 60,
                for: sessionStore.session
            )
        } else if focusStore.lobbySession?.durationSeconds != durationMinutes * 60 {
            await focusStore.updateLobbyDuration(durationMinutes * 60, for: sessionStore.session)
        }

        guard focusStore.lobbySession?.mode == .multiplayer else { return }

        await focusStore.inviteFriends(selectedFriends, for: sessionStore.session)
        selectedFriendIDs = []
        step = .multiplayerLobby
    }
}

private struct FriendInviteSelectionRow: View {
    let friend: UserProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(config: friend.avatarConfig, size: 40)

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
                            Label("Invite", systemImage: "person.badge.plus")
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
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text("Rewards unlock when everyone finishes")
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

    var body: some View {
        ZStack {
            PicoColors.appBackground
                .ignoresSafeArea()

            FocusCompleteCard(session: session)
                .padding(.horizontal, PicoSpacing.standard)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FocusCompleteCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var scoreStore: ScoreStore
    @EnvironmentObject private var focusStore: FocusStore

    let session: FocusSession

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

            rewardContent
                .padding(.top, PicoSpacing.standard)

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
                    focusStore.resetResult()
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
        case .lobby, .live:
            return "Session"
        }
    }

    private var scoreLabel: String {
        session.status == .completed ? "1 point" : "No score"
    }

    private var streakLabel: String {
        let streak = scoreStore.currentStreak
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
                    systemImage: "plus",
                    iconColor: PicoColors.primary
                )

                Spacer()

                FocusCompleteMetric(
                    title: streakLabel,
                    systemImage: "flame.fill",
                    iconColor: PicoColors.streakAccent
                )
            }
            .padding(.vertical, PicoSpacing.tiny)
        }
    }

    private func groupMetrics(for context: FocusCompletionContext) -> [FocusCompleteMetricModel] {
        var metrics = [
            FocusCompleteMetricModel(
                title: scoreLabel,
                systemImage: "plus",
                iconColor: PicoColors.primary
            ),
            FocusCompleteMetricModel(
                title: streakLabel,
                systemImage: "flame.fill",
                iconColor: PicoColors.streakAccent
            ),
            FocusCompleteMetricModel(
                title: "\(context.bondXP) bond XP",
                systemImage: "leaf.fill",
                iconColor: PicoColors.primary
            )
        ]

        if context.villageGrew {
            metrics.append(
                FocusCompleteMetricModel(
                    title: "Village grew",
                    systemImage: "leaf.circle.fill",
                    iconColor: PicoColors.success
                )
            )
        }

        return metrics
    }
}

private enum FocusCompleteAvatarLayout {
    static let spriteSide: CGFloat = 116
    static let avatarWidth: CGFloat = 132
    static let avatarHeight: CGFloat = 118
    static let celebrationHeight: CGFloat = 118
    static let namedCelebrationHeight: CGFloat = 150
    static let memberNameWidth: CGFloat = 124
    static let compactGroupAvatarSpacing: CGFloat = -44
}

private struct FocusCompleteGroupCelebrationView: View {
    let context: FocusCompletionContext
    let reduceMotion: Bool
    let showsConfetti: Bool

    private var usesScrollableMembers: Bool {
        context.members.count > 3
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsConfetti {
                    FocusCompleteConfettiView(reduceMotion: reduceMotion)
                        .frame(width: 280, height: FocusCompleteAvatarLayout.celebrationHeight)
                        .allowsHitTesting(false)
                }

                if usesScrollableMembers {
                    ScrollView(.horizontal) {
                        HStack(spacing: PicoSpacing.compact) {
                            ForEach(context.members) { member in
                                FocusCompleteGroupMemberPill(member: member)
                            }
                        }
                        .padding(.horizontal, PicoSpacing.compact)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: FocusCompleteAvatarLayout.namedCelebrationHeight)
                } else {
                    HStack(spacing: FocusCompleteAvatarLayout.compactGroupAvatarSpacing) {
                        ForEach(context.members) { member in
                            UserAvatar(
                                config: member.profile.avatarConfig,
                                maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
                                usesHappyIdle: true
                            )
                            .frame(
                                width: FocusCompleteAvatarLayout.avatarWidth,
                                height: FocusCompleteAvatarLayout.avatarHeight
                            )
                            .accessibilityLabel(Text(member.profile.displayName))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(
                height: usesScrollableMembers
                    ? FocusCompleteAvatarLayout.namedCelebrationHeight
                    : FocusCompleteAvatarLayout.celebrationHeight
            )
            .clipped()
        }
    }
}

private struct FocusCompleteGroupMemberPill: View {
    let member: FocusSessionMember

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            UserAvatar(
                config: member.profile.avatarConfig,
                maxSpriteSide: FocusCompleteAvatarLayout.spriteSide,
                usesHappyIdle: true
            )
            .frame(
                width: FocusCompleteAvatarLayout.avatarWidth,
                height: FocusCompleteAvatarLayout.avatarHeight
            )

            Text(member.profile.displayName)
                .font(PicoTypography.caption.weight(.semibold))
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: FocusCompleteAvatarLayout.memberNameWidth)
        }
        .frame(width: FocusCompleteAvatarLayout.avatarWidth)
        .accessibilityElement(children: .combine)
    }
}

private struct FocusCompleteMetricModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
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
                    systemImage: metric.systemImage,
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
    let systemImage: String
    let iconColor: Color

    var body: some View {
        Label {
            Text(title)
                .font(PicoTypography.caption.weight(.bold))
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(iconColor)
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct FocusMemberStatusRow: View {
    let member: FocusSessionMember

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            AvatarBadgeView(config: member.profile.avatarConfig, size: 40)

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
    let minutes = max(1, Int(ceil(Double(max(0, seconds)) / 60)))
    return "\(minutes) min"
}

private func clampedDurationMinutes(from seconds: Int) -> Int {
    min(120, max(1, seconds / 60))
}

private struct ProfilePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var scoreStore: ScoreStore
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
                        canCycleHats: availableHats.count >= 2,
                        previousHat: selectPreviousHat,
                        nextHat: selectNextHat
                    )

                    ProfileHatCollectionCard(selection: $avatarConfig, hats: availableHats)

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
            await scoreStore.loadScore(for: sessionStore.session)
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
        let hasUnlockedHat = avatarConfig.selectedHat.isUnlocked(with: scoreStore.score.score)
        let hasChanges = normalizedDisplayName != profile.displayName || avatarConfig != profile.avatarConfig
        return hasValidDisplayName && hasUnlockedHat && hasChanges
    }

    private var availableHats: [AvatarHat] {
        AvatarHat.allCases.filter { $0.isUnlocked(with: scoreStore.score.score) }
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
        let hats = availableHats
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

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: UserAvatarScene(
                    size: proxy.size,
                    hat: config.selectedHat,
                    maxSpriteSide: maxSpriteSide,
                    usesHappyIdle: usesHappyIdle
                ),
                options: [.allowsTransparency]
            )
            .id("\(config.selectedHat.id)-\(usesHappyIdle)")
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
    private var renderedSize: CGSize = .zero

    init(size: CGSize, hat: AvatarHat, maxSpriteSide: CGFloat, usesHappyIdle: Bool) {
        self.hat = hat
        self.maxSpriteSide = maxSpriteSide
        self.usesHappyIdle = usesHappyIdle
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

        let frames: [SKTexture]
        if usesHappyIdle {
            frames = AvatarHappyIdleFrames(hat: hat).frames(forRow: 0)
        } else {
            frames = AvatarIdleFrames(hat: hat).frames(forRow: 0)
        }
        guard let firstFrame = frames.first else { return }

        let sprite = SKSpriteNode(texture: firstFrame)
        let spriteSide = min(size.width * 0.72, size.height * 0.90, maxSpriteSide)
        sprite.size = CGSize(width: spriteSide, height: spriteSide)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.run(
            .repeatForever(.animate(with: frames, timePerFrame: 0.10)),
            withKey: Self.idleActionKey
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

            Image(systemName: "pencil")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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
            UserAvatar(config: avatarConfig)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
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
                    hatButton(systemImage: "chevron.left", action: previousHat)
                    hatButton(systemImage: "chevron.right", action: nextHat)
                }
            }
            .padding(.horizontal, PicoCreamCardStyle.contentPadding)
            .padding(.vertical, PicoSpacing.standard)
        }
        .picoCreamCard()
    }

    private func hatButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(canCycleHats ? PicoColors.textPrimary : PicoColors.textMuted)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(!canCycleHats)
    }
}

private struct ProfileHatCollectionCard: View {
    @Binding var selection: AvatarConfig
    let hats: [AvatarHat]

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            Text("Hat Collection")
                .font(PicoTypography.body.weight(.semibold))
                .foregroundStyle(PicoColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PicoSpacing.standard) {
                    ForEach(hats) { hat in
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

                Text(hat.name)
                    .font(PicoTypography.caption)
                    .foregroundStyle(isSelected ? PicoColors.textPrimary : PicoColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 82)
            .frame(minHeight: 96)
            .contentShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(hat.name) hat"))
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

            TextField("Display name", text: $displayName)
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
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
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
            Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
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
