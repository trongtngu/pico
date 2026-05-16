//
//  AuthSessionStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var ownedStoreItemIDs: Set<String> = []
    @Published private(set) var ownedHats: Set<AvatarHat> = [.none]
    @Published private(set) var ownedIslandIDs: Set<String> = [PicoIsland.original.backendID]
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isProfileLoading = false
    @Published private(set) var isProfileSaving = false
    @Published private(set) var profileNotice: String?
    @Published var notice: String?

    private let authService: AuthService
    private var hasLoadedProfile = false
    private var hasAttemptedSessionRestore = false
    private var hasStartedAuthSessionObservation = false
    private var authSessionTask: Task<Void, Never>?

    init(authService: AuthService? = nil) {
        self.authService = authService ?? AuthService()
    }

    deinit {
        authSessionTask?.cancel()
    }

    func signUp(
        email: String,
        password: String,
        username: String,
        displayName: String,
        avatarConfig: AvatarConfig
    ) async {
        await authenticate {
            try await authService.signUp(
                email: email,
                password: password,
                username: username,
                displayName: displayName,
                avatarConfig: avatarConfig
            )
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate {
            try await authService.signIn(email: email, password: password)
        }
    }

    func signInWithApple(idToken: String, nonce: String?, fullName: PersonNameComponents?) async {
        await authenticate {
            try await authService.signInWithApple(idToken: idToken, nonce: nonce)
        }

        await applyOAuthDisplayNameIfNeeded(Self.normalizedDisplayName(from: fullName))
    }

    func signInWithGoogle() async {
        var displayName: String?

        await authenticate {
            let tokens = try await GoogleSignInClient.signIn()
            displayName = tokens.displayName
            return try await authService.signInWithGoogle(
                idToken: tokens.idToken,
                accessToken: tokens.accessToken,
                nonce: tokens.nonce
            )
        }

        await applyOAuthDisplayNameIfNeeded(displayName)
    }

    func validateUsernameAvailability(_ username: String) async -> Bool {
        guard !isLoading else { return false }

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isLoading = true
        notice = nil
        defer { isLoading = false }

        do {
            let isAvailable = try await authService.isUsernameAvailable(normalizedUsername)
            if !isAvailable {
                notice = AuthServiceError.usernameUnavailable.errorDescription
            }
            return isAvailable
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signOut() {
        session = nil
        notice = nil
        resetProfile()
        Task {
            try? await authService.signOut()
        }
    }

    func restoreSessionIfNeeded() async {
        startAuthSessionObservationIfNeeded()
        guard !hasAttemptedSessionRestore else { return }
        hasAttemptedSessionRestore = true
        await restoreSession()
    }

    func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        await loadProfile()
    }

    func reloadProfile() async {
        hasLoadedProfile = false
        await loadProfile()
    }

    func refreshSessionIfNeeded() async {
        do {
            if let session = try await authService.validSession() {
                applySession(session)
            }
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func updateProfile(username: String, displayName: String, avatarConfig: AvatarConfig) async {
        guard let session, !isProfileSaving else { return }
        guard avatarConfig.selectedHat.isOwned(in: ownedHats) else {
            profileNotice = "You do not own that hat."
            return
        }

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil else {
            profileNotice = "That username is not available."
            return
        }

        let previousProfile = profile
        isProfileSaving = true
        profileNotice = nil
        defer { isProfileSaving = false }

        do {
            if previousProfile?.username != normalizedUsername {
                let isUsernameAvailable = try await authService.isUsernameAvailable(normalizedUsername)
                if !isUsernameAvailable {
                    throw AuthServiceError.usernameUnavailable
                }
            }

            profile = try await authService.updateProfile(
                username: normalizedUsername,
                displayName: displayName,
                avatarConfig: avatarConfig,
                for: session
            )
            hasLoadedProfile = true
        } catch {
            profile = previousProfile
            profileNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func updateProfile(displayName: String, avatarConfig: AvatarConfig) async {
        guard let username = profile?.username else { return }
        await updateProfile(username: username, displayName: displayName, avatarConfig: avatarConfig)
    }

    func clearProfileNotice() {
        profileNotice = nil
    }

    private func applyOAuthDisplayNameIfNeeded(_ displayName: String?) async {
        guard let session, let currentProfile = profile else { return }

        let oauthDisplayName = String((displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !oauthDisplayName.isEmpty else { return }

        let shouldReplaceDisplayName = currentProfile.displayName == "Pico"
            || currentProfile.displayName.hasPrefix("pico_")
        guard shouldReplaceDisplayName else { return }

        do {
            profile = try await authService.updateProfile(
                username: currentProfile.username,
                displayName: oauthDisplayName,
                avatarConfig: currentProfile.avatarConfig,
                for: session
            )
            hasLoadedProfile = true
        } catch {
            profileNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func applyOwnedStoreItemIDs(_ itemIDs: Set<String>) {
        ownedStoreItemIDs = itemIDs
        ownedHats = Self.ownedHats(from: itemIDs)
        ownedIslandIDs = Self.ownedIslandIDs(from: itemIDs)
        profileNotice = nil
    }

    #if DEBUG
    static func preview(session: AuthSession? = nil, notice: String? = nil) -> AuthSessionStore {
        let store = AuthSessionStore()
        store.session = session
        store.notice = notice
        store.isRestoringSession = false
        store.profile = UserProfile(
            userID: AuthUser.preview.id,
            username: "tommy",
            displayName: "Tommy",
            avatarConfig: AvatarCatalog.defaultConfig
        )
        store.ownedStoreItemIDs = Set(StoreItem.previewOwnedItemIDs)
        store.ownedHats = Set(AvatarHat.allCases)
        store.ownedIslandIDs = Set(PicoIsland.allCases.map(\.backendID))
        store.hasLoadedProfile = true
        return store
    }
    #endif

    private func authenticate(_ operation: () async throws -> AuthResult) async {
        isLoading = true
        notice = nil
        defer { isLoading = false }

        do {
            let result = try await operation()
            notice = result.message
            resetProfile()
            if let session = result.session {
                applySession(session)
                try? await authService.syncUserTimezone(for: session)
                await loadProfileIfNeeded()
            } else {
                session = nil
                resetProfile()
            }
        } catch {
            guard !error.isCancellation else { return }
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restoreSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            guard let restoredSession = try await authService.restoreSession() else {
                return
            }

            applySession(restoredSession)
            resetProfile()
            try? await authService.syncUserTimezone(for: restoredSession)
            await loadProfileIfNeeded()
        } catch {
            session = nil
            resetProfile()
        }
    }

    private func applySession(_ nextSession: AuthSession) {
        if session?.user?.id != nextSession.user?.id {
            resetProfile()
        }
        session = nextSession
    }

    private func startAuthSessionObservationIfNeeded() {
        guard !hasStartedAuthSessionObservation else { return }
        hasStartedAuthSessionObservation = true

        authSessionTask = Task { [weak self] in
            guard let authService = await self?.authService else { return }

            for await session in authService.authSessionChanges() {
                await MainActor.run {
                    guard let self else { return }

                    if let session {
                        self.applySession(session)
                    } else {
                        self.session = nil
                        self.resetProfile()
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        guard let session else { return }

        isProfileLoading = true
        profileNotice = nil
        defer { isProfileLoading = false }

        do {
            let nextProfile = try await authService.fetchProfile(for: session)
            let nextOwnedStoreItemIDs = try await authService.fetchStoreInventoryItemIDs(for: session)
            profile = nextProfile
            applyOwnedStoreItemIDs(nextOwnedStoreItemIDs)
            hasLoadedProfile = true
        } catch {
            profileNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetProfile() {
        profile = nil
        ownedStoreItemIDs = []
        ownedHats = [.none]
        ownedIslandIDs = [PicoIsland.original.backendID]
        isProfileLoading = false
        isProfileSaving = false
        profileNotice = nil
        hasLoadedProfile = false
    }

    private static func ownedHats(from itemIDs: Set<String>) -> Set<AvatarHat> {
        let storeHats = itemIDs.compactMap { itemID -> AvatarHat? in
            guard itemID.hasPrefix("hat:"),
                  let rawValue = Int(itemID.dropFirst("hat:".count)) else {
                return nil
            }

            return AvatarHat(rawValue: rawValue)
        }

        return Set(storeHats).union([.none])
    }

    private static func ownedIslandIDs(from itemIDs: Set<String>) -> Set<String> {
        let storeIslands = itemIDs.compactMap { itemID -> String? in
            guard itemID.hasPrefix("island:") else { return nil }
            return String(itemID.dropFirst("island:".count))
        }

        return Set(storeIslands).union([PicoIsland.original.backendID])
    }

    private static func normalizedDisplayName(from fullName: PersonNameComponents?) -> String {
        guard let fullName else { return "" }
        let formattedName = PersonNameComponentsFormatter.localizedString(from: fullName, style: .medium)
        return String(formattedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

}

private extension StoreItem {
    static let previewOwnedItemIDs = [
        "island:sand",
        "hat:1",
        "hat:2",
        "hat:3",
        "hat:4",
        "hat:5"
    ]
}
