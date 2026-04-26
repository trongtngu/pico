//
//  ContentView.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

import SpriteKit
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        AuthGateView()
    }
}

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @State private var selectedTab: AppTab = .home
    @StateObject private var friendStore = FriendStore()
    @StateObject private var focusStore = FocusStore()
    @StateObject private var villageStore = VillageStore()
    @StateObject private var scoreStore = ScoreStore()

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.rootView
                        .navigationTitle(tab.title)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
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
}

private enum AppTab: String, CaseIterable, Identifiable {
    case home
    case friends
    case sessions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .friends:
            "Friends"
        case .sessions:
            "Sessions"
        case .settings:
            "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .friends:
            "person.2"
        case .sessions:
            "calendar"
        case .settings:
            "person.crop.circle"
        }
    }

    @ViewBuilder
    var rootView: some View {
        switch self {
        case .home:
            HomePage()
        case .friends:
            FriendsPage()
        case .sessions:
            FocusPage()
        case .settings:
            ProfilePage()
        }
    }
}

private struct HomePage: View {
    @EnvironmentObject private var scoreStore: ScoreStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var sessionStore: AuthSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VillageView(residents: villageStore.residents)
                    .frame(maxWidth: .infinity)
                    .frame(height: 430)
                    .padding(.horizontal, 6)

                if villageStore.isLoadingResidents {
                    HStack {
                        Text("Loading village")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                    .padding(.horizontal)
                }

                if let notice = villageStore.notice {
                    Text(notice)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                StreakCardView(
                    score: scoreStore.score.score,
                    currentStreak: scoreStore.currentStreak,
                    isLoading: scoreStore.isLoadingScore,
                    notice: scoreStore.notice
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
            await scoreStore.loadScore(for: sessionStore.session)
        }
        .refreshable {
            await villageStore.loadResidents(for: sessionStore.session)
            await scoreStore.loadScore(for: sessionStore.session)
        }
    }
}

private struct StreakCardView: View {
    let score: Int
    let currentStreak: Int
    let isLoading: Bool
    let notice: String?

    private var streakLabel: String {
        "\(currentStreak) day\(currentStreak == 1 ? "" : "s") streak"
    }

    private var nextHat: AvatarHat? {
        AvatarHat.allCases.first { $0.requiredScore > score }
    }

    private var hatProgressValue: Double {
        guard let nextHat else { return 10 }
        return Double(max(0, 10 - (nextHat.requiredScore - score)))
    }

    private var hatProgressLabel: String {
        guard let nextHat else { return "All hats unlocked" }
        return "\(Int(hatProgressValue))/10 points to \(nextHat.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "flame")
                    .foregroundStyle(.orange)

                Text(streakLabel)
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(hatProgressLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ProgressView(value: hatProgressValue, total: 10)
                    .progressViewStyle(.linear)
            }

            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
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
