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
    @Published private(set) var isLoading = false
    @Published private(set) var isProfileLoading = false
    @Published private(set) var isProfileSaving = false
    @Published private(set) var profileNotice: String?
    @Published var notice: String?

    private let authService: AuthService
    private var hasLoadedProfile = false

    init(authService: AuthService? = nil) {
        self.authService = authService ?? AuthService()
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

    func signOut() {
        session = nil
        notice = nil
        resetProfile()
    }

    func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        await loadProfile()
    }

    func reloadProfile() async {
        hasLoadedProfile = false
        await loadProfile()
    }

    func updateProfile(displayName: String, avatarConfig: AvatarConfig) async {
        guard let session, !isProfileSaving else { return }

        let previousProfile = profile
        isProfileSaving = true
        profileNotice = nil
        defer { isProfileSaving = false }

        do {
            profile = try await authService.updateProfile(
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

    #if DEBUG
    static func preview(session: AuthSession? = nil, notice: String? = nil) -> AuthSessionStore {
        let store = AuthSessionStore()
        store.session = session
        store.notice = notice
        store.profile = UserProfile(
            userID: AuthUser.preview.id,
            username: "tommy",
            displayName: "Tommy",
            avatarConfig: AvatarCatalog.defaultConfig
        )
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
            session = result.session
            notice = result.message
            resetProfile()
            if let session = result.session {
                try? await authService.syncUserTimezone(for: session)
                await loadProfileIfNeeded()
            }
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadProfile() async {
        guard let session else { return }

        isProfileLoading = true
        profileNotice = nil
        defer { isProfileLoading = false }

        do {
            profile = try await authService.fetchProfile(for: session)
            hasLoadedProfile = true
        } catch {
            profileNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetProfile() {
        profile = nil
        isProfileLoading = false
        isProfileSaving = false
        profileNotice = nil
        hasLoadedProfile = false
    }
}
