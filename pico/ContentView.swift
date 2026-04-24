//
//  ContentView.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        AuthGateView()
    }
}

struct AppShellView: View {
    @State private var selectedTab: AppTab = .home
    @StateObject private var friendStore = FriendStore()

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
            SessionsPage()
        case .settings:
            ProfilePage()
        }
    }
}

private struct HomePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore

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
        }
        .task {
            await sessionStore.loadProfileIfNeeded()
        }
    }
}

private struct SessionsPage: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Recent sessions") {
                    PlaceholderDetailView(title: "Recent Sessions")
                }
                NavigationLink("Session history") {
                    PlaceholderDetailView(title: "Session History")
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Session list and detail flows can be added here.")
            }
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
