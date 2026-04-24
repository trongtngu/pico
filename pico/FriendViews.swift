//
//  FriendViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SwiftUI

struct FriendsPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AddFriendPage()
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                }

                NavigationLink {
                    IncomingRequestsPage()
                } label: {
                    HStack {
                        Label("Incoming Requests", systemImage: "tray")
                        Spacer()
                        if !friendStore.incomingRequests.isEmpty {
                            Text("\(friendStore.incomingRequests.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if friendStore.isLoadingFriends {
                    HStack {
                        Text("Loading friends")
                        Spacer()
                        ProgressView()
                    }
                } else if friendStore.friends.isEmpty {
                    ContentUnavailableView {
                        Label("No friends yet", systemImage: "person.2")
                    } description: {
                        Text("Add a friend by searching for their username.")
                    }
                } else {
                    ForEach(friendStore.friends, id: \.userID) { friend in
                        NavigationLink {
                            FriendProfilePage(profile: friend)
                        } label: {
                            FriendProfileRowView(profile: friend)
                        }
                    }
                }
            } header: {
                Text("Friends")
            }

            if let notice = friendStore.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await loadFriendsData()
        }
        .refreshable {
            await loadFriendsData()
        }
    }

    private func loadFriendsData() async {
        await friendStore.loadFriends(for: sessionStore.session)
        await friendStore.loadIncomingRequests(for: sessionStore.session)
    }
}

private struct AddFriendPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @State private var username = ""

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isUsernameValid: Bool {
        normalizedUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil
    }

    private var canSearch: Bool {
        isUsernameValid && !friendStore.isSearching
    }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await search()
                        }
                    }
                    .onChange(of: username) {
                        let normalized = normalizedUsername
                        if username != normalized {
                            username = normalized
                        }
                        friendStore.resetSearch()
                    }

                Button {
                    Task {
                        await search()
                    }
                } label: {
                    HStack {
                        Text("Search")
                        Spacer()
                        if friendStore.isSearching {
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSearch)
            } footer: {
                Text("Enter the exact username.")
            }

            if let profile = friendStore.searchResult {
                Section {
                    FriendProfileRowView(profile: profile)

                    if isAlreadyFriend(profile) {
                        Text("You are already friends.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task {
                                await friendStore.sendRequest(to: profile, session: sessionStore.session)
                            }
                        } label: {
                            HStack {
                                Text("Send Friend Request")
                                Spacer()
                                if friendStore.isSendingRequest {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(friendStore.isSendingRequest)
                    }
                } header: {
                    Text("Result")
                }
            }

            if let searchNotice = friendStore.searchNotice {
                Section {
                    Text(searchNotice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add Friend")
        .onDisappear {
            friendStore.resetSearch()
        }
    }

    private func search() async {
        guard isUsernameValid else {
            friendStore.searchNotice = "Username must be 3 to 24 lowercase letters, numbers, or underscores."
            return
        }

        await friendStore.search(
            username: normalizedUsername,
            currentProfile: sessionStore.profile,
            session: sessionStore.session
        )
    }

    private func isAlreadyFriend(_ profile: UserProfile) -> Bool {
        friendStore.friends.contains { $0.userID == profile.userID }
    }
}

private struct IncomingRequestsPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore

    var body: some View {
        List {
            Section {
                if friendStore.isLoadingIncomingRequests {
                    HStack {
                        Text("Loading requests")
                        Spacer()
                        ProgressView()
                    }
                } else if friendStore.incomingRequests.isEmpty {
                    ContentUnavailableView {
                        Label("No incoming requests", systemImage: "tray")
                    } description: {
                        Text("Friend requests sent to you will appear here.")
                    }
                } else {
                    ForEach(friendStore.incomingRequests) { request in
                        VStack(alignment: .leading, spacing: 12) {
                            FriendProfileRowView(profile: request.requester)

                            HStack {
                                Button("Accept") {
                                    Task {
                                        await friendStore.accept(request, session: sessionStore.session)
                                    }
                                }
                                .disabled(friendStore.activeRequestID != nil)

                                Button("Reject", role: .destructive) {
                                    Task {
                                        await friendStore.reject(request, session: sessionStore.session)
                                    }
                                }
                                .disabled(friendStore.activeRequestID != nil)

                                Spacer()

                                if friendStore.activeRequestID == request.id {
                                    ProgressView()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let notice = friendStore.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Requests")
        .task {
            await friendStore.loadIncomingRequests(for: sessionStore.session)
        }
        .refreshable {
            await friendStore.loadIncomingRequests(for: sessionStore.session)
        }
    }
}

private struct FriendProfilePage: View {
    let profile: UserProfile

    var body: some View {
        VStack(spacing: 16) {
            AvatarBadgeView(config: profile.avatarConfig, size: 104)

            VStack(spacing: 6) {
                Text(profile.displayName)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
        .padding(.horizontal)
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FriendProfileRowView: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarBadgeView(config: profile.avatarConfig, size: 48)

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 4)
    }
}

#if DEBUG
struct FriendViews_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FriendsPage()
                .environmentObject(AuthSessionStore.preview(session: AuthSession.preview))
                .environmentObject(FriendStore.preview)
        }
    }
}
#endif
