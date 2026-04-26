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
            } else {
                await villageStore.loadResidents(for: sessionStore.session)
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

    private var usesDrawerNavigation: Bool {
        horizontalSizeClass == .compact
    }

    private var navigationContent: some View {
        NavigationStack {
            selectedTab.rootView(openFocus: {
                selectTab(.home)
            })
            .navigationTitle(selectedTab.title)
            .navigationBarTitleDisplayMode(selectedTab == .home ? .inline : .automatic)
            .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
            .toolbar {
                if usesDrawerNavigation {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isNavigationDrawerOpen = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .accessibilityLabel(Text("Open navigation"))
                    }
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
                Text("Pico")
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
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .frame(width: 24, height: 24)

                        if !isPersistent {
                            Text(tab.title)
                                .font(PicoTypography.body.weight(.semibold))

                            Spacer(minLength: 0)
                        }
                    }
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
            PicoColors.surface
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
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Village"
        case .friends:
            "Friends"
        case .settings:
            "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "square.grid.3x3"
        case .friends:
            "person.2"
        case .settings:
            "person.crop.circle"
        }
    }

    @ViewBuilder
    func rootView(openFocus: @escaping () -> Void) -> some View {
        switch self {
        case .home:
            HomePage()
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
    @State private var isStartFocusSheetPresented = false
    @State private var startFocusStep = StartFocusSheetStep.modePicker

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VillageHeroSection(
                        residents: villageStore.residents,
                        isLoading: villageStore.isLoadingResidents,
                        notice: villageStore.notice,
                        height: villageHeight(in: proxy.size)
                    )

                    ActiveSessionTimerSlot(session: focusStore.activeSession)
                }
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.vertical, PicoSpacing.compact)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .refreshable {
                await focusStore.refresh(for: sessionStore.session)
                await friendStore.loadFriends(for: sessionStore.session)
                await villageStore.loadResidents(for: sessionStore.session)
                await scoreStore.loadScore(for: sessionStore.session)
            }
            .safeAreaInset(edge: .bottom) {
                if focusStore.activeSession == nil {
                    HomeFocusBottomBar(
                        score: scoreStore.score.score,
                        currentStreak: scoreStore.currentStreak,
                        isLoadingScore: scoreStore.isLoadingScore,
                        scoreNotice: scoreStore.notice,
                        incomingInviteCount: focusStore.incomingInvites.count,
                        action: presentStartFocusSheet
                    )
                }
            }
        }
        .picoScreenBackground()
        .sheet(isPresented: $isStartFocusSheetPresented) {
            StartFocusSheet(
                step: $startFocusStep,
                isPresented: $isStartFocusSheetPresented
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(PicoColors.surface)
        }
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
            await scoreStore.loadScore(for: sessionStore.session)
        }
        .onChange(of: focusStore.resultSession) {
            guard focusStore.resultSession != nil else { return }
            isStartFocusSheetPresented = true
        }
        .onChange(of: focusStore.activeSession) {
            guard focusStore.activeSession != nil else { return }
            isStartFocusSheetPresented = false
        }
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

    private func villageHeight(in size: CGSize) -> CGFloat {
        return max(500, size.height - 118)
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
    let isLoading: Bool
    let notice: String?
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            VillageView(residents: residents)
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
    let currentStreak: Int
    let isLoadingScore: Bool
    let scoreNotice: String?
    let incomingInviteCount: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            CompactProgressStrip(
                score: score,
                currentStreak: currentStreak,
                isLoading: isLoadingScore,
                notice: scoreNotice
            )

            StartFocusCTA(incomingInviteCount: incomingInviteCount, action: action)
        }
        .padding(.horizontal, PicoSpacing.standard)
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
            HStack(spacing: PicoSpacing.iconTextGap) {
                Image(systemName: incomingInviteCount > 0 ? "person.2.badge.plus" : "plus")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(width: 30, height: 30)
                    .background(PicoColors.textOnPrimary.opacity(0.18))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Focus")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if incomingInviteCount > 0 {
                        Text("\(incomingInviteCount) invite\(incomingInviteCount == 1 ? "" : "s") waiting")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textOnPrimary.opacity(0.86))
                    }
                }

                Spacer(minLength: 0)
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
    let currentStreak: Int
    let isLoading: Bool
    let notice: String?

    private var streakLabel: String {
        "\(currentStreak) day\(currentStreak == 1 ? "" : "s") streak"
    }

    private var unlockedHatCount: Int {
        AvatarHat.allCases.filter { $0 != .none && $0.isUnlocked(with: score) }.count
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: PicoSpacing.compact) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(PicoColors.streakAccent)

                    Text(streakLabel)
                        .font(PicoTypography.body.weight(.bold))
                        .foregroundStyle(PicoColors.textPrimary)
                }

                Spacer(minLength: PicoSpacing.compact)

                if isLoading {
                    ProgressView()
                        .tint(PicoColors.primary)
                }
            }

            Text("\(unlockedHatCount) hats unlocked")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)

            ProgressView(value: hatProgressValue, total: hatProgressTotal)
                .progressViewStyle(.linear)
                .tint(PicoColors.primary)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)

            if let notice {
                Text(notice)
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(2)
            }
        }
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
        .padding(.horizontal, PicoSpacing.cardPadding)
        .padding(.top, PicoSpacing.section)
        .padding(.bottom, PicoSpacing.section)
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            await friendStore.loadFriends(for: sessionStore.session)
            await focusStore.refresh(for: sessionStore.session)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let resultSession = focusStore.resultSession {
            FocusCompleteSheetContent(
                isPresented: $isPresented,
                session: resultSession
            )
        } else if let lobbySession = focusStore.lobbySession {
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
                    .font(PicoTypography.sectionTitle)
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
                .picoCard(padding: PicoSpacing.standard, cornerRadius: PicoRadius.medium)
            } else if focusStore.incomingInvites.isEmpty {
                Text("No invites right now.")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .picoCard(padding: PicoSpacing.standard, cornerRadius: PicoRadius.medium)
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

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(alignment: .top, spacing: PicoSpacing.iconTextGap) {
                AvatarBadgeView(config: invite.host.avatarConfig, size: 40)

                VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                    Text(invite.host.displayName)
                        .font(PicoTypography.body.weight(.semibold))
                        .foregroundStyle(PicoColors.textPrimary)

                    Text("@\(invite.host.username) invited you")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)
                }

                Spacer(minLength: 0)

                FocusDurationBadge(seconds: invite.session.durationSeconds)
            }

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
                        .font(PicoTypography.caption.weight(.semibold))
                        .foregroundStyle(PicoColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(focusStore.activeInviteID != nil)
            }
        }
        .picoCard(padding: PicoSpacing.standard, cornerRadius: PicoRadius.medium)
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
        .background(PicoColors.surface)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
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
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))

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
            .padding(PicoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var titleColor: Color {
        isHighlighted ? PicoColors.textOnPrimary : PicoColors.textPrimary
    }

    private var iconColor: Color {
        PicoColors.primary
    }

    private var iconBackground: Color {
        isHighlighted ? PicoColors.textOnPrimary : PicoColors.softSurface
    }

    private var chevronColor: Color {
        isHighlighted ? PicoColors.textOnPrimary.opacity(0.86) : PicoColors.textMuted
    }

    private var rowBackground: Color {
        isHighlighted ? PicoColors.primary : PicoColors.surface
    }

    private var borderColor: Color {
        isHighlighted ? PicoColors.primary : PicoColors.border
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

            Slider(
                value: sliderValue,
                in: 1...120,
                step: 1
            )
            .tint(PicoColors.primary)
            .disabled(isDisabled)
            .padding(.horizontal, PicoSpacing.standard)
        }
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
            Text("Invite friends")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textPrimary)

            HStack(spacing: PicoSpacing.compact) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PicoColors.textMuted)

                TextField("Search friends", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .frame(height: 42)
            .background(PicoColors.softSurface)
            .clipShape(Capsule(style: .continuous))

	            ScrollView {
	                LazyVStack(spacing: PicoSpacing.compact) {
	                    if friendStore.isLoadingFriends && availableFriends.isEmpty {
	                        ProgressView("Loading friends")
	                            .tint(PicoColors.primary)
	                            .foregroundStyle(PicoColors.textSecondary)
	                            .frame(maxWidth: .infinity, alignment: .leading)
	                            .padding(.vertical, PicoSpacing.standard)
                    } else if availableFriends.isEmpty {
                        Text(searchText.isEmpty ? "No friends available to invite." : "No friends match that search.")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, PicoSpacing.standard)
                    } else {
                        ForEach(availableFriends, id: \.userID) { friend in
                            FriendInviteSelectionRow(
                                friend: friend,
                                isSelected: selectedFriendIDs.contains(friend.userID)
                            ) {
                                toggle(friend)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

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
            .padding(.vertical, PicoSpacing.tiny)
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
	                HStack(spacing: PicoSpacing.compact) {
	                    Image(systemName: "clock")
	                        .font(.system(size: 13, weight: .semibold, design: .rounded))
	                        .foregroundStyle(PicoColors.primary)
	
	                    Text(homeFormattedDurationMinutes(session.durationSeconds))
	                        .font(PicoTypography.caption)
	                        .foregroundStyle(PicoColors.textPrimary)
	                }
	                .padding(.horizontal, 10)
	                .padding(.vertical, 7)
	                .background(PicoColors.surface)
	                .clipShape(RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous))
	                .overlay(
	                    RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
	                        .stroke(PicoColors.border, lineWidth: 1)
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

private struct ActiveSessionTimerSlot: View {
    let session: FocusSession?
    private let slotHeight: CGFloat = 112
    private let timerTopSpacing: CGFloat = 18

    var body: some View {
        Group {
            if let session {
                ActiveSessionTimerStrip(session: session)
            } else {
                Color.clear
            }
        }
        .padding(.top, timerTopSpacing)
        .frame(maxWidth: .infinity)
        .frame(height: slotHeight, alignment: .top)
    }
}

private struct ActiveSessionTimerStrip: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
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
                await focusStore.completeCurrentSession(for: sessionStore.session)
            }
        }
    }

    private var canLeaveMultiplayer: Bool {
        session.mode == .multiplayer && !focusStore.isCurrentUserHost(sessionStore.session)
    }
}

private struct FocusCompleteSheetContent: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var scoreStore: ScoreStore
    @EnvironmentObject private var focusStore: FocusStore
    @Binding var isPresented: Bool

    let session: FocusSession

    private var avatarConfig: AvatarConfig {
        sessionStore.profile?.avatarConfig ?? AvatarCatalog.defaultConfig
    }

    private var unlockedHatCount: Int {
        AvatarHat.allCases.filter { $0 != .none && $0.isUnlocked(with: scoreStore.score.score) }.count
    }

    var body: some View {
        VStack(spacing: PicoSpacing.standard) {
            Text(resultTitle)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)

            AvatarBadgeView(config: avatarConfig, size: 112)

            HStack {
                Label(scoreLabel, systemImage: "plus.circle.fill")
                    .font(PicoTypography.body.weight(.bold))
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer()

                Label("\(scoreStore.currentStreak) day streak", systemImage: "flame.fill")
                    .font(PicoTypography.body.weight(.bold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .labelStyle(.titleAndIcon)
            }

            Text("\(unlockedHatCount) hats unlocked")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
            } else {
                Button("Done") {
                    focusStore.resetResult()
                    isPresented = false
                }
                .buttonStyle(PicoPrimaryButtonStyle())
            }
        }
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
        session.status == .completed ? "+1 point" : "No score"
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
	        .padding(.vertical, PicoSpacing.tiny)
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
    @State private var avatarConfig = AvatarCatalog.defaultConfig

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    ProfileIdleCharacterView(hat: avatarConfig.selectedHat)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)

                    Button {
                        avatarConfig = avatarConfig.withHat(nextHat)
                    } label: {
                        Label("Cycle Outfit", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(availableHats.count < 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if let profile = sessionStore.profile {
                    ProfileCardView(profile: profile)
                } else if sessionStore.isProfileLoading {
                    ProgressView("Loading profile")
                } else {
                    ProfileUnavailableView()
                }
            }

            if let profile = sessionStore.profile {
                Section {
                    Text("@\(profile.username)")
                        .foregroundStyle(.secondary)

                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile")
                }

                Section {
                    AvatarPickerView(selection: $avatarConfig, score: scoreStore.score.score)
                } header: {
                    Text("Outfit")
                }

                Section {
                    Button {
                        Task {
                            await sessionStore.updateProfile(
                                displayName: displayName,
                                avatarConfig: avatarConfig
                            )
                        }
                    } label: {
                        HStack {
                            Text("Save Profile")
                            Spacer()
                            if sessionStore.isProfileSaving {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSave || sessionStore.isProfileSaving)
                }
            }

            if let profileNotice = sessionStore.profileNotice {
                Section {
                    Text(profileNotice)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    sessionStore.signOut()
                }
            }
        }
        .task {
            await sessionStore.loadProfileIfNeeded()
            await scoreStore.loadScore(for: sessionStore.session)
            syncEditableProfile()
        }
        .onChange(of: sessionStore.profile) {
            syncEditableProfile()
        }
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

    private var nextHat: AvatarHat {
        let hats = availableHats
        guard let currentIndex = hats.firstIndex(of: avatarConfig.selectedHat) else { return .none }
        return hats[(currentIndex + 1) % hats.count]
    }

    private func syncEditableProfile() {
        guard let profile = sessionStore.profile else { return }
        displayName = profile.displayName
        avatarConfig = profile.avatarConfig
    }
}

private struct ProfileIdleCharacterView: View {
    let hat: AvatarHat

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: ProfileIdleCharacterScene(
                    size: proxy.size,
                    hat: hat
                ),
                options: [.allowsTransparency]
            )
            .id(hat.id)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .accessibilityLabel(Text("Animated profile character"))
    }
}

private final class ProfileIdleCharacterScene: SKScene {
    private static let idleActionKey = "idle"

    private let hat: AvatarHat
    private var renderedSize: CGSize = .zero

    init(size: CGSize, hat: AvatarHat) {
        self.hat = hat
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

        let frames = AvatarIdleFrames(hat: hat).frames(forRow: 0)
        guard let firstFrame = frames.first else { return }

        let sprite = SKSpriteNode(texture: firstFrame)
        let spriteSide = min(size.width * 0.72, size.height * 0.90, 150)
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

    var body: some View {
        HStack(spacing: 14) {
            AvatarBadgeView(config: profile.avatarConfig, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
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
