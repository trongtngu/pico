//
//  FriendStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

@MainActor
final class FriendStore: ObservableObject {
    @Published private(set) var friends: [UserProfile] = []
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var searchResult: UserProfile?
    @Published private(set) var isLoadingFriends = false
    @Published private(set) var isLoadingIncomingRequests = false
    @Published private(set) var isSearching = false
    @Published private(set) var isSendingRequest = false
    @Published private(set) var activeRequestID: UUID?
    @Published var notice: String?
    @Published var searchNotice: String?

    private let friendService: FriendService

    init(friendService: FriendService? = nil) {
        self.friendService = friendService ?? FriendService()
    }

    func loadFriends(for session: AuthSession?) async {
        guard let session, !isLoadingFriends else { return }

        isLoadingFriends = true
        notice = nil
        defer { isLoadingFriends = false }

        do {
            friends = try await friendService.fetchFriends(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadIncomingRequests(for session: AuthSession?) async {
        guard let session, !isLoadingIncomingRequests else { return }

        isLoadingIncomingRequests = true
        notice = nil
        defer { isLoadingIncomingRequests = false }

        do {
            incomingRequests = try await friendService.fetchIncomingRequests(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func search(username: String, currentProfile: UserProfile?, session: AuthSession?) async {
        guard let session else { return }
        let normalizedUsername = username.normalizedFriendUsername
        guard !normalizedUsername.isEmpty else {
            searchResult = nil
            searchNotice = nil
            return
        }

        if normalizedUsername == currentProfile?.username {
            searchResult = nil
            searchNotice = "You cannot add yourself as a friend."
            return
        }

        isSearching = true
        searchResult = nil
        searchNotice = nil
        defer { isSearching = false }

        do {
            if let profile = try await friendService.findProfile(username: normalizedUsername, for: session) {
                searchResult = profile
            } else {
                searchNotice = "No user found for @\(normalizedUsername)."
            }
        } catch {
            searchNotice = displayMessage(for: error)
        }
    }

    func sendRequest(to profile: UserProfile, session: AuthSession?) async {
        guard let session, !isSendingRequest else { return }

        isSendingRequest = true
        searchNotice = nil
        defer { isSendingRequest = false }

        do {
            try await friendService.sendFriendRequest(to: profile.username, for: session)
            searchResult = nil
            searchNotice = "Friend request sent to @\(profile.username)."
        } catch {
            searchNotice = displayMessage(for: error)
        }
    }

    func accept(_ request: FriendRequest, session: AuthSession?) async {
        guard let session, activeRequestID == nil else { return }

        activeRequestID = request.id
        notice = nil
        defer { activeRequestID = nil }

        do {
            try await friendService.acceptFriendRequest(request.id, for: session)
            incomingRequests.removeAll { $0.id == request.id }
            await loadFriends(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func reject(_ request: FriendRequest, session: AuthSession?) async {
        guard let session, activeRequestID == nil else { return }

        activeRequestID = request.id
        notice = nil
        defer { activeRequestID = nil }

        do {
            try await friendService.rejectFriendRequest(request.id, for: session)
            incomingRequests.removeAll { $0.id == request.id }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func resetSearch() {
        searchResult = nil
        searchNotice = nil
    }

    #if DEBUG
    static var preview: FriendStore {
        let store = FriendStore()
        store.friends = [
            UserProfile(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                username: "casey",
                displayName: "Casey",
                avatarConfig: AvatarConfig(key: "avatar_2")
            )
        ]
        store.incomingRequests = [
            FriendRequest(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                requester: UserProfile(
                    userID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                    username: "riley",
                    displayName: "Riley",
                    avatarConfig: AvatarConfig(key: "avatar_3")
                ),
                createdAt: "2026-04-25T00:00:00Z"
            )
        ]
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension String {
    var normalizedFriendUsername: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
