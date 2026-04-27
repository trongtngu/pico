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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PicoSpacing.standard) {
                HStack(spacing: PicoSpacing.compact) {
                    NavigationLink {
                        AddFriendPage()
                    } label: {
                        FriendActionButtonContent(
                            title: "Add friend",
                            systemImage: "person.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    NavigationLink {
                        IncomingRequestsPage()
                    } label: {
                        FriendActionButtonContent(
                            title: "Incoming requests",
                            systemImage: "tray",
                            badgeCount: friendStore.incomingRequests.count
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: PicoSpacing.compact) {
                    Text("Friends")
                        .font(PicoTypography.caption.weight(.bold))
                        .foregroundStyle(PicoColors.textSecondary)
                        .textCase(.uppercase)

                    friendsContent
                }

                if let notice = friendStore.notice {
                    FriendNoticeCard(text: notice)
                }
            }
            .padding(PicoSpacing.standard)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
        .task {
            await loadFriendsData()
        }
        .refreshable {
            await loadFriendsData()
        }
    }

    @ViewBuilder
    private var friendsContent: some View {
        if friendStore.isLoadingFriends {
            HStack(spacing: PicoSpacing.standard) {
                Text("Loading friends")
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                ProgressView()
                    .tint(PicoColors.primary)
            }
            .padding(PicoSpacing.standard)
            .picoCreamCard()
        } else if friendStore.friends.isEmpty {
            FriendEmptyStateCard(
                title: "No friends yet",
                message: "Add a friend by searching for their username.",
                systemImage: "person.2"
            )
        } else {
            FriendsListCard(friends: friendStore.friends)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PicoSpacing.standard) {
                VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                    HStack(spacing: PicoSpacing.compact) {
                        Image(systemName: "at")
                            .foregroundStyle(PicoColors.textMuted)

                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .foregroundStyle(PicoColors.textPrimary)
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
                    }
                    .padding(.horizontal, PicoSpacing.iconTextGap)
                    .frame(height: 46)
                    .background(PicoCreamCardStyle.controlBackground)
                    .clipShape(Capsule(style: .continuous))

                    Text("Enter the exact username.")
                        .font(PicoTypography.caption)
                        .foregroundStyle(PicoColors.textSecondary)

                    Button {
                        Task {
                            await search()
                        }
                    } label: {
                        HStack {
                            Text("Search")
                            if friendStore.isSearching {
                                ProgressView()
                                    .tint(PicoColors.textOnPrimary)
                            }
                        }
                    }
                    .buttonStyle(PicoPrimaryButtonStyle())
                    .disabled(!canSearch)
                    .opacity(canSearch ? 1 : 0.62)
                }
                .picoCreamCard(padding: PicoCreamCardStyle.contentPadding)

                if let profile = friendStore.searchResult {
                    VStack(alignment: .leading, spacing: PicoSpacing.standard) {
                        Text("Result")
                            .font(PicoTypography.caption.weight(.bold))
                            .foregroundStyle(PicoColors.textSecondary)
                            .textCase(.uppercase)

                        FriendProfileRowView(profile: profile)

                        if isAlreadyFriend(profile) {
                            Text("You are already friends.")
                                .font(PicoTypography.caption)
                                .foregroundStyle(PicoColors.textSecondary)
                        } else {
                            Button {
                                Task {
                                    await friendStore.sendRequest(to: profile, session: sessionStore.session)
                                }
                            } label: {
                                HStack {
                                    Text("Send friend request")
                                    if friendStore.isSendingRequest {
                                        ProgressView()
                                            .tint(PicoColors.textOnPrimary)
                                    }
                                }
                            }
                            .buttonStyle(PicoPrimaryButtonStyle())
                            .disabled(friendStore.isSendingRequest)
                            .opacity(friendStore.isSendingRequest ? 0.62 : 1)
                        }
                    }
                    .picoCreamCard(padding: PicoCreamCardStyle.contentPadding)
                }

                if let searchNotice = friendStore.searchNotice {
                    FriendNoticeCard(text: searchNotice)
                }
            }
            .padding(PicoSpacing.standard)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .navigationTitle("Add Friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
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
        ScrollView {
            LazyVStack(spacing: PicoSpacing.standard) {
                requestsContent

                if let notice = friendStore.notice {
                    FriendNoticeCard(text: notice)
                }
            }
            .padding(PicoSpacing.standard)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .navigationTitle("Incoming Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
        .task {
            await friendStore.loadIncomingRequests(for: sessionStore.session)
        }
        .refreshable {
            await friendStore.loadIncomingRequests(for: sessionStore.session)
        }
    }

    @ViewBuilder
    private var requestsContent: some View {
        if friendStore.isLoadingIncomingRequests {
            HStack(spacing: PicoSpacing.standard) {
                Text("Loading requests")
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)

                Spacer(minLength: 0)

                ProgressView()
                    .tint(PicoColors.primary)
            }
            .padding(PicoSpacing.standard)
            .picoCreamCard()
        } else if friendStore.incomingRequests.isEmpty {
            FriendEmptyStateCard(
                title: "No incoming requests",
                message: "Friend requests sent to you will appear here.",
                systemImage: "tray"
            )
        } else {
            ForEach(friendStore.incomingRequests) { request in
                IncomingFriendRequestCard(request: request)
            }
        }
    }
}

private struct FriendProfilePage: View {
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: PicoSpacing.standard) {
                VStack(spacing: PicoSpacing.standard) {
                    AvatarBadgeView(config: profile.avatarConfig, size: 112)

                    VStack(spacing: PicoSpacing.tiny) {
                        Text(profile.displayName)
                            .font(PicoTypography.cardTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        Text("@\(profile.username)")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .picoCreamCard(padding: PicoSpacing.section)

                HStack(spacing: PicoSpacing.iconTextGap) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(PicoColors.primary)

                    VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                        Text("Friend")
                            .font(PicoTypography.body.weight(.semibold))
                            .foregroundStyle(PicoColors.textPrimary)

                        Text("You can invite @\(profile.username) to focus sessions.")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .picoCreamCard(padding: PicoCreamCardStyle.contentPadding)
            }
            .padding(PicoSpacing.standard)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
    }
}

private struct FriendProfileRowView: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            AvatarBadgeView(config: profile.avatarConfig, size: 48)

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text(profile.displayName)
                    .font(PicoTypography.body.weight(.semibold))
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)

                Text("@\(profile.username)")
                    .font(PicoTypography.caption)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct FriendActionButtonContent: View {
    let title: String
    let systemImage: String
    var badgeCount: Int = 0

    var body: some View {
        HStack(spacing: PicoSpacing.tiny) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PicoColors.primary)

            Text(title)
                .font(PicoTypography.caption.weight(.semibold))
                .foregroundStyle(PicoColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PicoColors.textOnPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PicoColors.primary)
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, PicoSpacing.compact)
        .background(PicoCreamCardStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
        )
        .shadow(color: PicoShadow.raisedCardColor, radius: PicoShadow.raisedCardRadius, x: PicoShadow.raisedCardX, y: PicoShadow.raisedCardY)
    }
}

private struct FriendsListCard: View {
    let friends: [UserProfile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(friends.enumerated()), id: \.element.userID) { index, friend in
                NavigationLink {
                    FriendProfilePage(profile: friend)
                } label: {
                    HStack(spacing: PicoSpacing.iconTextGap) {
                        FriendProfileRowView(profile: friend)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(PicoColors.textMuted)
                    }
                    .padding(.horizontal, PicoSpacing.cardPadding)
                    .padding(.vertical, PicoSpacing.standard)
                }
                .buttonStyle(.plain)

                if index < friends.count - 1 {
                    PicoCardDivider()
                }
            }
        }
        .picoCreamCard()
    }
}

private struct IncomingFriendRequestCard: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    let request: FriendRequest

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            FriendProfileRowView(profile: request.requester)

            HStack(spacing: PicoSpacing.iconTextGap) {
                Button {
                    Task {
                        await friendStore.accept(request, session: sessionStore.session)
                    }
                } label: {
                    HStack {
                        Text("Accept")
                        if friendStore.activeRequestID == request.id {
                            ProgressView()
                                .tint(PicoColors.textOnPrimary)
                        }
                    }
                }
                .buttonStyle(FriendCompactPrimaryButtonStyle())
                .disabled(friendStore.activeRequestID != nil)

                Button {
                    Task {
                        await friendStore.reject(request, session: sessionStore.session)
                    }
                } label: {
                    Text("Decline")
                }
                .buttonStyle(FriendCompactCardButtonStyle(foreground: PicoColors.textPrimary))
                .disabled(friendStore.activeRequestID != nil)
            }
        }
        .picoCreamCard(padding: PicoCreamCardStyle.contentPadding)
    }
}

private struct FriendCompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.caption.weight(.bold))
            .foregroundStyle(PicoColors.textOnPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .fill(PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct FriendCompactCardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var foreground: Color = PicoColors.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.caption.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .fill(PicoCreamCardStyle.background.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
            )
            .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct FriendEmptyStateCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(PicoColors.primary)

            Text(title)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(PicoSpacing.cardPadding)
        .picoCreamCard()
    }
}

private struct FriendNoticeCard: View {
    let text: String

    var body: some View {
        Text(text)
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
