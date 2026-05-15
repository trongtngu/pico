//
//  FocusStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

private enum FocusFailureReason {
    static let interrupted = "interrupted"
    static let leftMultiplayer = "left_multiplayer"
}

struct FocusCompletionContext: Equatable {
    let members: [FocusSessionMember]
    let currentUserID: UUID
    let preCompletionVillageResidentIDs: Set<UUID>?

    var peerMembers: [FocusSessionMember] {
        members.filter { $0.userID != currentUserID }
    }

    func isNewPeer(_ member: FocusSessionMember) -> Bool {
        guard member.userID != currentUserID,
              let preCompletionVillageResidentIDs else {
            return false
        }

        return !preCompletionVillageResidentIDs.contains(member.userID)
    }
}

struct FocusFailureContext: Equatable {
    let failedMember: FocusSessionMember?
    let failedMemberDisplayName: String?
    let failedByUserID: UUID?
    let failureReason: String?
    let currentUserID: UUID?

    var isCurrentUserFailure: Bool {
        guard let failedByUserID, let currentUserID else { return false }
        return failedByUserID == currentUserID
    }

    var isMemberLeaveFailure: Bool {
        failureReason == FocusFailureReason.leftMultiplayer
    }
}

@MainActor
final class FocusStore: ObservableObject {
    static let defaultDurationSeconds = 30 * 60
    // Temporary testing override; restore to 10 * 60 after short-session testing.
    static let minimumDurationSeconds = 10
    static let maximumDurationSeconds = 120 * 60

    @Published private(set) var lobbySession: FocusSession?
    @Published private(set) var activeSession: FocusSession?
    @Published private(set) var resultSession: FocusSession?
    @Published private(set) var sessionDetail: FocusSessionDetail?
    @Published private(set) var incomingInvites: [FocusSessionInvite] = []
    @Published private(set) var isCreating = false
    @Published private(set) var isLoadingInvites = false
    @Published private(set) var isUpdatingConfig = false
    @Published private(set) var isInvitingMembers = false
    @Published private(set) var isStarting = false
    @Published private(set) var isFinishing = false
    @Published private(set) var activeInviteID: UUID?
    @Published private(set) var activeInvitedFriendIDs: Set<UUID> = []
    @Published private(set) var hasPendingResultSync = false
    private(set) var completionContext: FocusCompletionContext?
    private(set) var failureContext: FocusFailureContext?
    @Published var notice: String?

    private let focusService: FocusService
    private let userDefaults: UserDefaults
    private let savedStateKey = "pico.focus.saved-state.v4"
    private var pendingBackgroundInterruptionTask: Task<Void, Never>?
    private var realtimeSubscription: FocusRealtimeSubscription?
    private var realtimeChannelID: String?
    private var isRealtimeRefreshing = false
    private var isDeviceLocking = false
    private var selectedIslandID = PicoIsland.original.backendID
    private var knownVillageResidentIDs: Set<UUID>?

    init(focusService: FocusService? = nil, userDefaults: UserDefaults = .standard) {
        self.focusService = focusService ?? FocusService()
        self.userDefaults = userDefaults
    }

    var isIslandSelectionLocked: Bool {
        lobbySession != nil || activeSession != nil
    }

    deinit {
        pendingBackgroundInterruptionTask?.cancel()
        Task { @MainActor [subscription = realtimeSubscription] in
            subscription?.stop()
        }
    }

    func restoreSavedState(for authSession: AuthSession?) async {
        guard let authSession, let userID = authSession.user?.id else {
            clearInMemoryState()
            knownVillageResidentIDs = nil
            return
        }

        subscribeToRealtime(for: authSession, sessionID: nil)

        if let savedState = loadSavedState(), savedState.userID == userID, let pendingResult = savedState.pendingResult {
            hasPendingResultSync = true
            lobbySession = nil
            activeSession = nil
            sessionDetail = nil
            let optimisticSession = pendingResult.optimisticSession(
                from: savedState.session,
                failedByUserID: authSession.user?.id
            )
            failureContext = makeFailureContext(
                for: optimisticSession,
                detail: nil,
                currentUserID: authSession.user?.id
            )
            resultSession = optimisticSession
            await retryPendingResult(for: authSession)
            return
        }

        if let savedState = loadSavedState(), savedState.userID == userID {
            applyRestoredSession(savedState.session)
        }

        await syncOpenSessionState(for: authSession)
        if activeSession?.remainingSeconds() == 0 {
            await completeCurrentSession(for: authSession)
        }
    }

    func refresh(for authSession: AuthSession?) async {
        await retryPendingResult(for: authSession)
        guard let authSession else { return }

        await syncOpenSessionState(for: authSession)
    }

    func loadIncomingInvites(for authSession: AuthSession?) async {
        guard let authSession, !isLoadingInvites else { return }

        isLoadingInvites = true
        defer { isLoadingInvites = false }

        do {
            incomingInvites = try await focusService.fetchIncomingInvites(for: authSession)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func updateSelectedIslandID(_ islandID: String?) {
        guard let islandID, !islandID.isEmpty else {
            selectedIslandID = PicoIsland.original.backendID
            return
        }

        selectedIslandID = islandID
    }

    func createLobby(
        mode: FocusSessionMode,
        durationSeconds: Int? = nil,
        for authSession: AuthSession?
    ) async {
        guard let authSession, !isCreating, !hasPendingResultSync else { return }

        let requestedDuration = durationSeconds ?? Self.defaultDurationSeconds
        let clampedDuration = min(Self.maximumDurationSeconds, max(Self.minimumDurationSeconds, requestedDuration))
        isCreating = true
        notice = nil
        defer { isCreating = false }

        do {
            let session = try await focusService.createSession(
                mode: mode,
                durationSeconds: clampedDuration,
                islandID: selectedIslandID,
                for: authSession
            )
            applyOpenSession(session, authSession: authSession)
            await refreshDetailIfNeeded(for: session, authSession: authSession)
            subscribeToRealtime(for: authSession, sessionID: session.id)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func updateLobbyDuration(_ durationSeconds: Int, for authSession: AuthSession?) async {
        guard
            let authSession,
            let lobbySession,
            lobbySession.isLobby,
            !isUpdatingConfig,
            isCurrentUserHost(authSession)
        else {
            return
        }

        let clampedDuration = min(Self.maximumDurationSeconds, max(Self.minimumDurationSeconds, durationSeconds))
        guard clampedDuration != lobbySession.durationSeconds else { return }

        isUpdatingConfig = true
        notice = nil
        defer { isUpdatingConfig = false }

        do {
            let session = try await focusService.updateSessionConfig(
                lobbySession.id,
                durationSeconds: clampedDuration,
                for: authSession
            )
            applyOpenSession(session, authSession: authSession)
            await refreshDetailIfNeeded(for: session, authSession: authSession)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func inviteFriends(_ friends: [UserProfile], for authSession: AuthSession?) async {
        guard
            let authSession,
            let lobbySession,
            lobbySession.mode == .multiplayer,
            lobbySession.isLobby,
            !isInvitingMembers,
            isCurrentUserHost(authSession)
        else {
            return
        }

        let invitedIDs = friends.map(\.userID)
        guard !invitedIDs.isEmpty else { return }

        isInvitingMembers = true
        activeInvitedFriendIDs = Set(invitedIDs)
        notice = nil
        defer {
            isInvitingMembers = false
            activeInvitedFriendIDs = []
        }

        do {
            let session = try await focusService.inviteMembers(invitedIDs, to: lobbySession.id, for: authSession)
            applyOpenSession(session, authSession: authSession)
            await refreshDetailIfNeeded(for: session, authSession: authSession)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func joinInvite(_ invite: FocusSessionInvite, for authSession: AuthSession?) async {
        guard let authSession, activeInviteID == nil else { return }

        activeInviteID = invite.id
        notice = nil
        defer { activeInviteID = nil }

        do {
            let session = try await focusService.joinSession(
                invite.id,
                islandID: selectedIslandID,
                for: authSession
            )
            incomingInvites.removeAll { $0.id == invite.id }
            applyOpenSession(session, authSession: authSession)
            guard !session.isFinished else {
                subscribeToRealtime(for: authSession, sessionID: nil)
                await loadIncomingInvites(for: authSession)
                return
            }
            await refreshDetailIfNeeded(for: session, authSession: authSession)
            subscribeToRealtime(for: authSession, sessionID: session.id)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func declineInvite(_ invite: FocusSessionInvite, for authSession: AuthSession?) async {
        guard let authSession, activeInviteID == nil else { return }

        activeInviteID = invite.id
        notice = nil
        defer { activeInviteID = nil }

        do {
            _ = try await focusService.declineSession(invite.id, for: authSession)
            incomingInvites.removeAll { $0.id == invite.id }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func startLobbySession(for authSession: AuthSession?) async {
        guard
            let authSession,
            let lobbySession,
            lobbySession.isLobby,
            !isStarting,
            isCurrentUserHost(authSession)
        else {
            return
        }

        isStarting = true
        notice = nil
        defer { isStarting = false }

        do {
            let session = try await focusService.startSession(lobbySession.id, for: authSession)
            applyOpenSession(session, authSession: authSession)
            await refreshDetailIfNeeded(for: session, authSession: authSession)
            if session.isLive {
                AnalyticsService.track(.focusSessionStarted(
                    sessionType: session.analyticsSessionType,
                    durationMinutes: session.analyticsDurationMinutes,
                    entryPoint: "home"
                ))
            }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    @discardableResult
    func cancelLobbySession(for authSession: AuthSession?) async -> Bool {
        guard
            let authSession,
            let lobbySession,
            lobbySession.isLobby,
            !isFinishing,
            isCurrentUserHost(authSession)
        else {
            return false
        }

        isFinishing = true
        notice = nil
        defer { isFinishing = false }

        do {
            _ = try await focusService.cancelSessionLobby(lobbySession.id, for: authSession)
            self.lobbySession = nil
            self.activeSession = nil
            self.sessionDetail = nil
            self.resultSession = nil
            self.completionContext = nil
            self.failureContext = nil
            self.hasPendingResultSync = false
            clearSavedState()
            subscribeToRealtime(for: authSession, sessionID: nil)
            await loadIncomingInvites(for: authSession)
            return true
        } catch {
            notice = displayMessage(for: error)
            return false
        }
    }

    func completeCurrentSession(
        for authSession: AuthSession?,
        preCompletionVillageResidentIDs: Set<UUID>? = nil
    ) async {
        guard let authSession, let session = activeSession ?? liveSavedSession() else { return }
        await finish(
            session,
            pendingResult: .complete,
            authSession: authSession,
            preCompletionVillageResidentIDs: preCompletionVillageResidentIDs ?? knownVillageResidentIDs
        )
    }

    func interruptCurrentSession(
        for authSession: AuthSession?,
        reason: String = "user_cancelled"
    ) async {
        guard let authSession, let session = activeSession ?? liveSavedSession() else { return }
        await finish(
            session,
            pendingResult: .interrupt(reason: reason),
            authSession: authSession,
            preCompletionVillageResidentIDs: nil,
            interruptionReason: reason
        )
    }

    func leaveCurrentMultiplayerSession(for authSession: AuthSession?) async {
        guard
            let authSession,
            let session = lobbySession ?? activeSession,
            session.mode == .multiplayer,
            !isFinishing
        else {
            return
        }

        if session.isLive {
            await finish(
                session,
                pendingResult: .interrupt(reason: FocusFailureReason.leftMultiplayer),
                authSession: authSession,
                preCompletionVillageResidentIDs: nil,
                interruptionReason: FocusFailureReason.leftMultiplayer
            )
            return
        }

        guard !isCurrentUserHost(authSession) else { return }

        isFinishing = true
        notice = nil
        defer { isFinishing = false }

        do {
            let syncedSession = try await focusService.leaveSession(session.id, for: authSession)
            let previousDetail = sessionDetail
            let nextResultSession = session.isLive
                ? (syncedSession.status == .failed ? syncedSession : session.failed())
                : nil
            lobbySession = nil
            activeSession = nil
            sessionDetail = nil
            if let nextResultSession {
                failureContext = makeFailureContext(
                    for: nextResultSession,
                    detail: previousDetail,
                    currentUserID: authSession.user?.id
                )
            } else {
                failureContext = nil
            }
            resultSession = nextResultSession
            if session.isLive {
                AnalyticsService.track(.focusSessionInterrupted(
                    sessionType: session.analyticsSessionType,
                    durationMinutes: session.analyticsDurationMinutes,
                    interruptionReason: "left_multiplayer"
                ))
            }
            completionContext = nil
            hasPendingResultSync = false
            clearSavedState()
            subscribeToRealtime(for: authSession, sessionID: nil)
            await loadIncomingInvites(for: authSession)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func retryPendingResult(for authSession: AuthSession?) async {
        guard let authSession, let savedState = loadSavedState(), let pendingResult = savedState.pendingResult else {
            hasPendingResultSync = false
            return
        }

        lobbySession = nil
        activeSession = nil
        sessionDetail = nil
        let optimisticSession = pendingResult.optimisticSession(
            from: savedState.session,
            failedByUserID: authSession.user?.id
        )
        failureContext = makeFailureContext(
            for: optimisticSession,
            detail: nil,
            currentUserID: authSession.user?.id
        )
        resultSession = optimisticSession
        hasPendingResultSync = true
        notice = nil
        isFinishing = true
        defer { isFinishing = false }

        do {
            let syncResult = try await sync(
                pendingResult,
                session: savedState.session,
                authSession: authSession
            )
            await applySyncedPendingResult(
                syncResult.session,
                pendingResult: pendingResult,
                originalSession: savedState.session,
                authSession: authSession
            )
        } catch {
            guard !error.isCancellation else { return }
            if await recoverAlreadyAppliedPendingResult(
                pendingResult,
                session: savedState.session,
                authSession: authSession
            ) {
                return
            }

            if error.isMissingFocusSessionState {
                await clearStalePendingResult(
                    pendingResult,
                    session: savedState.session,
                    authSession: authSession
                )
                return
            }

            hasPendingResultSync = true
            notice = displayMessage(for: error) ?? "Result saved locally. It will retry when the app opens again."
        }
    }

    func handleDeviceWillLock() {
        isDeviceLocking = true
        pendingBackgroundInterruptionTask?.cancel()
        pendingBackgroundInterruptionTask = nil
    }

    func handleDeviceDidUnlock(for authSession: AuthSession?) async {
        isDeviceLocking = false
        await completeIfDue(for: authSession)
        await refresh(for: authSession)
    }

    func handleSceneBecameActive(for authSession: AuthSession?) async {
        pendingBackgroundInterruptionTask?.cancel()
        pendingBackgroundInterruptionTask = nil
        isDeviceLocking = false
        await completeIfDue(for: authSession)
        await refresh(for: authSession)
    }

    func handleSceneMovedToBackground(
        for authSession: AuthSession?,
        protectedDataAvailable: Bool
    ) {
        guard let authSession, let activeSession, activeSession.isLive else { return }
        if activeSession.remainingSeconds() == 0 {
            Task {
                await completeCurrentSession(for: authSession)
            }
            return
        }

        guard protectedDataAvailable && !isDeviceLocking else { return }

        pendingBackgroundInterruptionTask?.cancel()
        pendingBackgroundInterruptionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.interruptCurrentSession(for: authSession, reason: "app_background")
        }
    }

    func resetResult() {
        guard !hasPendingResultSync else { return }
        resultSession = nil
        sessionDetail = nil
        completionContext = nil
        failureContext = nil
        notice = nil
    }

    func updateKnownVillageResidentIDs(_ residentIDs: Set<UUID>?) {
        knownVillageResidentIDs = residentIDs
    }

    func isCurrentUserHost(_ authSession: AuthSession?) -> Bool {
        guard let userID = authSession?.user?.id else { return false }
        if let detail = sessionDetail {
            return detail.isHost(userID)
        }
        return lobbySession?.ownerID == userID || activeSession?.ownerID == userID
    }

    #if DEBUG
    static var preview: FocusStore {
        let store = FocusStore()
        store.lobbySession = FocusSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            ownerID: AuthUser.preview.id,
            mode: .solo,
            status: .lobby,
            durationSeconds: defaultDurationSeconds,
            startedAt: nil,
            plannedEndAt: nil,
            endedAt: nil
        )
        return store
    }
    #endif

    private func applyRestoredSession(_ session: FocusSession) {
        switch session.status {
        case .lobby:
            lobbySession = session
            activeSession = nil
            resultSession = nil
            completionContext = nil
            failureContext = nil
            notice = nil
        case .active:
            lobbySession = nil
            activeSession = session
            resultSession = nil
            completionContext = nil
            failureContext = nil
            notice = nil
        case .completed, .failed, .cancelled:
            applyFinishedSession(session)
        }
    }

    private func applyOpenSession(_ session: FocusSession, authSession: AuthSession) {
        switch session.status {
        case .lobby:
            lobbySession = session
            activeSession = nil
            resultSession = nil
            completionContext = nil
            failureContext = nil
            notice = nil
            saveState(LocalFocusState(userID: authSession.user?.id ?? session.ownerID, session: session, pendingResult: nil))
        case .active:
            lobbySession = nil
            activeSession = session
            resultSession = nil
            completionContext = nil
            failureContext = nil
            notice = nil
            saveState(LocalFocusState(userID: authSession.user?.id ?? session.ownerID, session: session, pendingResult: nil))
        case .completed, .failed, .cancelled:
            applyFinishedSession(session, currentUserID: authSession.user?.id)
            clearSavedState()
        }
    }

    private func applyFinishedSession(
        _ session: FocusSession,
        detail: FocusSessionDetail? = nil,
        currentUserID: UUID? = nil
    ) {
        if session.status == .cancelled {
            clearFocusSessionState()
            return
        }

        lobbySession = nil
        activeSession = nil
        sessionDetail = nil
        failureContext = makeFailureContext(for: session, detail: detail, currentUserID: currentUserID)
        resultSession = session
        notice = nil
    }

    private func refreshDetailIfNeeded(for session: FocusSession, authSession: AuthSession) async {
        guard session.mode == .multiplayer else {
            sessionDetail = nil
            return
        }

        do {
            let detail = try await focusService.fetchSessionDetail(session.id, for: authSession)
            if detail.session.isFinished {
                applyFinishedSession(detail.session, detail: detail, currentUserID: authSession.user?.id)
                clearSavedState()
                subscribeToRealtime(for: authSession, sessionID: nil)
                await loadIncomingInvites(for: authSession)
                return
            }

            sessionDetail = detail
            applyOpenSession(detail.session, authSession: authSession)
        } catch {
            if error.isMissingFocusSessionState {
                clearFocusSessionState()
                subscribeToRealtime(for: authSession, sessionID: nil)
                _ = await syncOpenSessions(for: authSession)
                await loadIncomingInvites(for: authSession)
                return
            }

            notice = displayMessage(for: error)
        }
    }

    private func syncOpenSessionState(for authSession: AuthSession) async {
        let previousActiveSession = activeSession ?? liveSavedSession()
        let previousSession = activeSession ?? lobbySession ?? liveSavedSession()

        do {
            let detail = try await focusService.fetchCurrentSessionDetail(for: authSession)
            guard let detail else {
                if await applyFinishedPreviousSessionIfNeeded(previousSession, authSession: authSession) {
                    return
                }

                if let previousActiveSession,
                   previousActiveSession.isLive,
                   previousActiveSession.remainingSeconds() == 0 {
                    await finish(
                        previousActiveSession,
                        pendingResult: .complete,
                        authSession: authSession,
                        preCompletionVillageResidentIDs: knownVillageResidentIDs
                    )
                    return
                }

                if resultSession != nil || hasPendingResultSync {
                    lobbySession = nil
                    activeSession = nil
                    sessionDetail = nil
                    subscribeToRealtime(for: authSession, sessionID: nil)
                    await loadIncomingInvites(for: authSession)
                    return
                }

                clearFocusSessionState()
                subscribeToRealtime(for: authSession, sessionID: nil)
                await loadIncomingInvites(for: authSession)
                return
            }

            if detail.session.isFinished {
                applyFinishedSession(detail.session, detail: detail, currentUserID: authSession.user?.id)
                clearSavedState()
                subscribeToRealtime(for: authSession, sessionID: nil)
                await loadIncomingInvites(for: authSession)
                return
            }

            applyOpenSession(detail.session, authSession: authSession)
            sessionDetail = detail.session.mode == .multiplayer ? detail : nil
            subscribeToRealtime(for: authSession, sessionID: detail.session.id)
            await loadIncomingInvites(for: authSession)
        } catch {
            if error.isMissingFocusSessionState {
                clearFocusSessionState()
                subscribeToRealtime(for: authSession, sessionID: nil)
                await loadIncomingInvites(for: authSession)
                return
            }

            notice = displayMessage(for: error)
        }
    }

    private func completeIfDue(for authSession: AuthSession?) async {
        guard let session = activeSession, session.isLive, session.remainingSeconds() == 0 else { return }
        await completeCurrentSession(for: authSession)
    }

    private func syncOpenSessions(for authSession: AuthSession) async -> FocusSessionSyncResult? {
        do {
            return try await focusService.syncOpenSessions(for: authSession)
        } catch {
            guard !error.isCancellation else { return nil }
            notice = displayMessage(for: error)
            return nil
        }
    }

    private func finish(
        _ session: FocusSession,
        pendingResult: PendingFocusResult,
        authSession: AuthSession,
        preCompletionVillageResidentIDs: Set<UUID>?,
        interruptionReason: String = "user_cancelled"
    ) async {
        guard !isFinishing else { return }

        isFinishing = true
        notice = nil

        let capturedCompletionContext = makeCompletionContext(
            for: session,
            pendingResult: pendingResult,
            authSession: authSession,
            preCompletionVillageResidentIDs: preCompletionVillageResidentIDs
        )
        let capturedDetail = sessionDetail
        let optimisticSession = pendingResult.optimisticSession(
            from: session,
            failedByUserID: authSession.user?.id
        )
        lobbySession = nil
        activeSession = nil
        sessionDetail = nil
        completionContext = capturedCompletionContext
        failureContext = makeFailureContext(
            for: optimisticSession,
            detail: capturedDetail,
            currentUserID: authSession.user?.id
        )
        resultSession = optimisticSession
        hasPendingResultSync = true
        saveState(LocalFocusState(
            userID: authSession.user?.id ?? session.ownerID,
            session: session,
            pendingResult: pendingResult
        ))
        trackFocusSessionFinished(
            session,
            pendingResult: pendingResult,
            interruptionReason: interruptionReason
        )

        do {
            let syncResult = try await sync(
                pendingResult,
                session: session,
                authSession: authSession
            )
            await applySyncedPendingResult(
                syncResult.session,
                pendingResult: pendingResult,
                originalSession: session,
                authSession: authSession
            )
        } catch {
            if !error.isCancellation {
                let recovered = await recoverAlreadyAppliedPendingResult(
                    pendingResult,
                    session: session,
                    authSession: authSession
                )
                if recovered {
                    return
                }

                if error.isMissingFocusSessionState {
                    await clearStalePendingResult(
                        pendingResult,
                        session: session,
                        authSession: authSession
                    )
                } else {
                    notice = displayMessage(for: error) ?? "Result saved locally. It will retry when the app opens again."
                }
            }
        }

        isFinishing = false
    }

    private func applySyncedPendingResult(
        _ syncedSession: FocusSession,
        pendingResult: PendingFocusResult,
        originalSession: FocusSession,
        authSession: AuthSession
    ) async {
        let optimisticSession = pendingResult.optimisticSession(
            from: originalSession,
            failedByUserID: authSession.user?.id
        )
        let nextResultSession = pendingResult.shouldUseSavedSession(syncedSession, originalSession: originalSession)
            ? syncedSession
            : optimisticSession
        failureContext = makeFailureContext(
            for: nextResultSession,
            detail: nil,
            currentUserID: authSession.user?.id
        )
        resultSession = nextResultSession
        hasPendingResultSync = false
        notice = nil
        clearSavedState()
        subscribeToRealtime(for: authSession, sessionID: nil)
        await loadIncomingInvites(for: authSession)
    }

    private func recoverAlreadyAppliedPendingResult(
        _ pendingResult: PendingFocusResult,
        session: FocusSession,
        authSession: AuthSession
    ) async -> Bool {
        guard let userID = authSession.user?.id else { return false }

        do {
            let detail = try await focusService.fetchSessionDetail(session.id, for: authSession)
            guard pendingResult.isAlreadyApplied(in: detail, for: userID) else { return false }

            await applySyncedPendingResult(
                detail.session,
                pendingResult: pendingResult,
                originalSession: session,
                authSession: authSession
            )
            return true
        } catch {
            return false
        }
    }

    private func clearStalePendingResult(
        _ pendingResult: PendingFocusResult,
        session: FocusSession,
        authSession: AuthSession
    ) async {
        let optimisticSession = pendingResult.optimisticSession(
            from: session,
            failedByUserID: authSession.user?.id
        )
        failureContext = makeFailureContext(
            for: optimisticSession,
            detail: nil,
            currentUserID: authSession.user?.id
        )
        resultSession = optimisticSession
        hasPendingResultSync = false
        notice = nil
        clearSavedState()
        subscribeToRealtime(for: authSession, sessionID: nil)
        await loadIncomingInvites(for: authSession)
    }

    private func makeCompletionContext(
        for session: FocusSession,
        pendingResult: PendingFocusResult,
        authSession: AuthSession,
        preCompletionVillageResidentIDs: Set<UUID>?
    ) -> FocusCompletionContext? {
        guard
            pendingResult == .complete,
            session.mode == .multiplayer,
            let currentUserID = authSession.user?.id,
            let detail = sessionDetail,
            detail.session.id == session.id
        else {
            return nil
        }

        let joinedMembers = detail.members.filter { $0.status == .joined }
        guard joinedMembers.contains(where: { $0.userID == currentUserID }),
              joinedMembers.contains(where: { $0.userID != currentUserID }) else {
            return nil
        }

        return FocusCompletionContext(
            members: joinedMembers,
            currentUserID: currentUserID,
            preCompletionVillageResidentIDs: preCompletionVillageResidentIDs
        )
    }

    private func sync(
        _ pendingResult: PendingFocusResult,
        session: FocusSession,
        authSession: AuthSession
    ) async throws -> FocusSyncResult {
        switch pendingResult {
        case .complete:
            let completedSession = try await focusService.completeSession(session.id, for: authSession)
            return FocusSyncResult(session: completedSession)
        case .interrupt(let reason):
            let session = try await focusService.interruptSession(session.id, reason: reason, for: authSession)
            return FocusSyncResult(session: session)
        }
    }

    private func subscribeToRealtime(for authSession: AuthSession, sessionID: UUID?) {
        guard let userID = authSession.user?.id else { return }
        let nextChannelID = "focus-\(userID)-\(sessionID?.uuidString ?? "invites")"
        guard nextChannelID != realtimeChannelID else { return }

        realtimeSubscription?.stop()
        realtimeChannelID = nextChannelID

        guard let subscription = FocusRealtimeSubscription(accessToken: authSession.accessToken, onChange: { [weak self] in
            Task { @MainActor in
                await self?.refreshFromRealtime(for: authSession)
            }
        }) else {
            return
        }

        realtimeSubscription = subscription
        subscription.start(channelID: nextChannelID, sessionID: sessionID, userID: userID)
    }

    private func refreshFromRealtime(for authSession: AuthSession) async {
        guard !isRealtimeRefreshing else { return }
        isRealtimeRefreshing = true
        defer { isRealtimeRefreshing = false }

        await syncOpenSessionState(for: authSession)
        if let updatedSession = activeSession, updatedSession.isLive, updatedSession.remainingSeconds() == 0 {
            await completeCurrentSession(for: authSession)
        }
    }

    private func liveSavedSession() -> FocusSession? {
        guard let savedState = loadSavedState(), savedState.session.isLive else { return nil }
        return savedState.session
    }

    private func saveState(_ state: LocalFocusState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: savedStateKey)
    }

    private func loadSavedState() -> LocalFocusState? {
        if let data = userDefaults.data(forKey: savedStateKey),
           let savedState = try? JSONDecoder().decode(LocalFocusState.self, from: data) {
            return savedState
        }

        return nil
    }

    private func clearSavedState() {
        userDefaults.removeObject(forKey: savedStateKey)
    }

    private func clearFocusSessionState() {
        pendingBackgroundInterruptionTask?.cancel()
        pendingBackgroundInterruptionTask = nil
        lobbySession = nil
        activeSession = nil
        resultSession = nil
        sessionDetail = nil
        hasPendingResultSync = false
        completionContext = nil
        failureContext = nil
        notice = nil
        clearSavedState()
    }

    private func clearInMemoryState() {
        lobbySession = nil
        activeSession = nil
        resultSession = nil
        sessionDetail = nil
        incomingInvites = []
        hasPendingResultSync = false
        completionContext = nil
        failureContext = nil
        realtimeSubscription?.stop()
        realtimeSubscription = nil
        realtimeChannelID = nil
    }

    private func applyFinishedPreviousSessionIfNeeded(
        _ session: FocusSession?,
        authSession: AuthSession
    ) async -> Bool {
        guard let session else { return false }

        do {
            let detail = try await focusService.fetchSessionDetail(session.id, for: authSession)
            guard detail.session.isFinished else { return false }

            applyFinishedSession(detail.session, detail: detail, currentUserID: authSession.user?.id)
            clearSavedState()
            subscribeToRealtime(for: authSession, sessionID: nil)
            await loadIncomingInvites(for: authSession)
            return true
        } catch {
            return false
        }
    }

    private func makeFailureContext(
        for session: FocusSession?,
        detail: FocusSessionDetail?,
        currentUserID: UUID?
    ) -> FocusFailureContext? {
        guard let session, session.status == .failed else { return nil }

        return FocusFailureContext(
            failedMember: detail?.member(for: session.failedByUserID),
            failedMemberDisplayName: detail?.member(for: session.failedByUserID)?.profile.displayName,
            failedByUserID: session.failedByUserID,
            failureReason: session.failureReason,
            currentUserID: currentUserID
        )
    }

    private func displayMessage(for error: Error) -> String? {
        guard !error.isCancellation else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func trackFocusSessionFinished(
        _ session: FocusSession,
        pendingResult: PendingFocusResult,
        interruptionReason: String
    ) {
        switch pendingResult {
        case .complete:
            AnalyticsService.track(.focusSessionCompleted(
                sessionType: session.analyticsSessionType,
                durationMinutes: session.analyticsDurationMinutes,
                completedSuccessfully: true
            ))
        case .interrupt:
            AnalyticsService.track(.focusSessionInterrupted(
                sessionType: session.analyticsSessionType,
                durationMinutes: session.analyticsDurationMinutes,
                interruptionReason: interruptionReason
            ))
        }
    }
}

private extension FocusSession {
    var analyticsSessionType: String {
        mode.rawValue
    }

    var analyticsDurationMinutes: Int {
        max(1, Int(ceil(Double(durationSeconds) / 60.0)))
    }
}

private extension Error {
    var isMissingFocusSessionState: Bool {
        guard
            let focusError = self as? FocusServiceError,
            case let .requestFailed(message) = focusError
        else {
            return false
        }

        return message.localizedCaseInsensitiveContains("P0002")
            || message.localizedCaseInsensitiveContains("No focus session")
            || message.localizedCaseInsensitiveContains("No focus lobby")
            || message.localizedCaseInsensitiveContains("No joined focus session membership")
            || message.localizedCaseInsensitiveContains("No open focus session")
    }
}

private struct FocusSyncResult {
    let session: FocusSession
}

private struct LocalFocusState: Codable, Equatable {
    let userID: UUID
    let session: FocusSession
    let pendingResult: PendingFocusResult?
}

private enum PendingFocusResult: Codable, Equatable {
    case complete
    case interrupt(reason: String)

    private enum CodingKeys: String, CodingKey {
        case action
        case failureReason
    }

    private enum Action: String, Codable {
        case complete
        case interrupt
    }

    func shouldUseSavedSession(_ savedSession: FocusSession, originalSession: FocusSession) -> Bool {
        switch self {
        case .complete:
            originalSession.mode == .solo || savedSession.isFinished
        case .interrupt:
            originalSession.mode == .solo || savedSession.isFinished
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(Action.self, forKey: .action)

        switch action {
        case .complete:
            self = .complete
        case .interrupt:
            let reason = try container.decodeIfPresent(String.self, forKey: .failureReason)
                ?? FocusFailureReason.interrupted
            self = .interrupt(reason: reason)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .complete:
            try container.encode(Action.complete, forKey: .action)
        case .interrupt(let reason):
            try container.encode(Action.interrupt, forKey: .action)
            try container.encode(reason, forKey: .failureReason)
        }
    }

    func optimisticSession(from session: FocusSession, failedByUserID: UUID? = nil) -> FocusSession {
        switch self {
        case .complete:
            session.completed()
        case .interrupt(let reason):
            session.failed(failedByUserID: failedByUserID, failureReason: reason)
        }
    }

    func isAlreadyApplied(in detail: FocusSessionDetail, for userID: UUID) -> Bool {
        switch self {
        case .complete:
            detail.member(for: userID)?.isCompleted == true
        case .interrupt:
            detail.member(for: userID)?.isInterrupted == true || detail.session.status == .failed
        }
    }
}
