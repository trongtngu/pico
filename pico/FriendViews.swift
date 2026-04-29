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
    @EnvironmentObject private var villageStore: VillageStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PicoSpacing.standard) {
                HStack(spacing: PicoSpacing.compact) {
                    NavigationLink {
                        AddFriendPage()
                    } label: {
                        FriendActionButtonContent(
                            title: "Add friend",
                            icon: .userPlusRegular
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    NavigationLink {
                        IncomingRequestsPage()
                    } label: {
                        FriendActionButtonContent(
                            title: "Requests",
                            icon: .inboxRegular,
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
                icon: .usersRegular
            )
        } else {
            FriendsListCard(friends: friendStore.friends)
        }
    }

    private func loadFriendsData() async {
        await friendStore.loadFriends(for: sessionStore.session)
        await friendStore.loadIncomingRequests(for: sessionStore.session)
        await villageStore.loadResidents(for: sessionStore.session)
    }
}

private struct AddFriendPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @State private var searchText = ""
    @State private var requestedProfileIDs: Set<UUID> = []

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            UserProfileSearchList(
                searchText: $searchText,
                placeholder: "Search users",
                isLoading: friendStore.isSearching,
                loadingText: "Searching users",
                emptyText: emptySearchText,
                profiles: friendStore.profileSearchResults
            ) { profile in
                AddFriendSearchResultRow(
                    profile: profile,
                    isAlreadyFriend: isAlreadyFriend(profile),
                    isRequestSent: requestedProfileIDs.contains(profile.userID),
                    isSendingRequest: friendStore.activeRequestUserID == profile.userID,
                    isSendDisabled: friendStore.isSendingRequest
                ) {
                    Task {
                        if await friendStore.sendRequest(to: profile, session: sessionStore.session) {
                            requestedProfileIDs.insert(profile.userID)
                        }
                    }
                }
            }

            if let searchNotice = friendStore.searchNotice {
                FriendNoticeCard(text: searchNotice)
            }

            Spacer(minLength: 0)
        }
        .padding(PicoSpacing.standard)
        .background(PicoColors.appBackground.ignoresSafeArea())
        .navigationTitle("Add Friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
        .task {
            await friendStore.loadFriends(for: sessionStore.session)
        }
        .task(id: normalizedSearchText) {
            await searchProfiles(matching: normalizedSearchText)
        }
        .onDisappear {
            friendStore.resetSearch()
        }
    }

    private var emptySearchText: String? {
        normalizedSearchText.count < 2 ? nil : "No users match that search."
    }

    private func searchProfiles(matching query: String) async {
        guard query.count >= 2 else {
            friendStore.resetSearch()
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        await friendStore.searchProfiles(
            matching: query,
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
                icon: .inboxRegular
            )
        } else {
            ForEach(friendStore.incomingRequests) { request in
                IncomingFriendRequestCard(request: request)
            }
        }
    }
}

private struct FriendProfilePage: View {
    @EnvironmentObject private var villageStore: VillageStore

    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(spacing: PicoSpacing.standard) {
                VStack(spacing: PicoSpacing.standard) {
                    AvatarBadgeView(
                        config: profile.avatarConfig,
                        size: 112,
                        scarf: villageStore.scarf(for: profile.userID)
                    )

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
    @EnvironmentObject private var villageStore: VillageStore

    let profile: UserProfile

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            AvatarBadgeView(
                config: profile.avatarConfig,
                size: 48,
                scarf: villageStore.scarf(for: profile.userID)
            )

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

struct UserProfileSearchList<RowContent: View>: View {
    @Binding var searchText: String
    let placeholder: String
    let isLoading: Bool
    let loadingText: String
    let emptyText: String?
    let profiles: [UserProfile]
    let rowContent: (UserProfile) -> RowContent

    init(
        searchText: Binding<String>,
        placeholder: String,
        isLoading: Bool,
        loadingText: String,
        emptyText: String?,
        profiles: [UserProfile],
        @ViewBuilder rowContent: @escaping (UserProfile) -> RowContent
    ) {
        _searchText = searchText
        self.placeholder = placeholder
        self.isLoading = isLoading
        self.loadingText = loadingText
        self.emptyText = emptyText
        self.profiles = profiles
        self.rowContent = rowContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PicoSpacing.standard) {
            HStack(spacing: PicoSpacing.compact) {
                PicoIcon(.magnifyingGlassRegular, size: 16)
                    .foregroundStyle(PicoColors.textMuted)

                TextField(placeholder, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(PicoColors.textPrimary)
            }
            .padding(.horizontal, PicoSpacing.iconTextGap)
            .frame(height: 42)
            .background(PicoCreamCardStyle.controlBackground)
            .clipShape(Capsule(style: .continuous))

            ScrollView {
                LazyVStack(spacing: PicoSpacing.compact) {
                    if isLoading && profiles.isEmpty {
                        ProgressView(loadingText)
                            .tint(PicoColors.primary)
                            .foregroundStyle(PicoColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
                    } else if profiles.isEmpty, let emptyText {
                        Text(emptyText)
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
                    } else {
                        ForEach(profiles, id: \.userID) { profile in
                            rowContent(profile)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct AddFriendSearchResultRow: View {
    let profile: UserProfile
    let isAlreadyFriend: Bool
    let isRequestSent: Bool
    let isSendingRequest: Bool
    let isSendDisabled: Bool
    let sendRequest: () -> Void

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            FriendProfileRowView(profile: profile)

            trailingAction
        }
        .picoCreamCard(showsShadow: false, padding: PicoCreamCardStyle.sheetCardPadding)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isAlreadyFriend {
            statusLabel("Friends", icon: .usersSolid)
        } else if isRequestSent {
            statusLabel("Sent", icon: .paperAirplaneRegular)
        } else {
            Button(action: sendRequest) {
                HStack(spacing: PicoSpacing.tiny) {
                    Text("Add")
                    if isSendingRequest {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(PicoColors.textOnPrimary)
                    }
                }
                .font(PicoTypography.caption.weight(.bold))
                .foregroundStyle(PicoColors.textOnPrimary)
                .padding(.horizontal, PicoSpacing.iconTextGap)
                .frame(height: 34)
                .background(PicoColors.primary)
                .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
            .opacity(isSendDisabled && !isSendingRequest ? 0.62 : 1)
        }
    }

    private func statusLabel(_ text: String, icon: PicoIconAsset) -> some View {
        HStack(spacing: PicoSpacing.tiny) {
            PicoIcon(icon, size: 14)
            Text(text)
        }
        .font(PicoTypography.caption.weight(.bold))
        .foregroundStyle(PicoColors.textSecondary)
        .lineLimit(1)
    }
}

private struct FriendActionButtonContent: View {
    let title: String
    let icon: PicoIconAsset
    var badgeCount: Int = 0

    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            PicoIcon(icon, size: 15)
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

                        PicoIcon(.chevronRightRegular, size: 14)
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
    let icon: PicoIconAsset

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            PicoIcon(icon, size: 28)
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
                .environmentObject(VillageStore.preview)
        }
    }
}
#endif
