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
        store.isRestoringSession = false
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
