//
//  ContentView.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

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
        .task(id: sessionStore.session?.user?.id) {
            await focusStore.restoreSavedState(for: sessionStore.session)
            if sessionStore.session == nil {
                villageStore.clear()
            } else {
                await villageStore.loadResidents(for: sessionStore.session)
            }
        }
        .onChange(of: focusStore.resultSession) {
            guard focusStore.resultSession?.status == .completed else { return }
            Task {
                await villageStore.loadResidents(for: sessionStore.session)
            }
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
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore

    var body: some View {
        List {
            Section {
                if let profile = sessionStore.profile {
                    ProfileCardView(profile: profile)
                } else if sessionStore.isProfileLoading {
                    HStack {
                        Text("Loading profile")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    ProfileUnavailableView()
                }
            }

            if let profileNotice = sessionStore.profileNotice {
                Section {
                    Text(profileNotice)
                        .foregroundStyle(.secondary)

                    Button("Retry") {
                        Task {
                            await sessionStore.reloadProfile()
                        }
                    }
                }
            }

            Section {
                NavigationLink("Open overview") {
                    PlaceholderDetailView(title: "Home Overview")
                }
            } header: {
                Text("Home")
            } footer: {
                Text("A starting point for the primary dashboard experience.")
            }

            Section {
                NavigationLink {
                    VillagePage()
                } label: {
                    HStack {
                        Label("Village", systemImage: "house")
                        Spacer()
                        if villageStore.isLoadingResidents {
                            ProgressView()
                        } else {
                            Text("\(villageStore.residents.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Residents appear after completed multiplayer focus sessions.")
            }
        }
        .task {
            await sessionStore.loadProfileIfNeeded()
            await villageStore.loadResidents(for: sessionStore.session)
        }
    }
}

private struct ProfilePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @State private var displayName = ""
    @State private var avatarConfig = AvatarCatalog.defaultConfig

    var body: some View {
        Form {
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
                    AvatarPickerView(selection: $avatarConfig)
                } header: {
                    Text("Avatar")
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
        let hasChanges = normalizedDisplayName != profile.displayName || avatarConfig != profile.avatarConfig
        return hasValidDisplayName && hasChanges
    }

    private func syncEditableProfile() {
        guard let profile = sessionStore.profile else { return }
        displayName = profile.displayName
        avatarConfig = profile.avatarConfig
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
