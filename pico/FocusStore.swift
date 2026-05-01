//
//  FocusStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

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

@MainActor
final class FocusStore: ObservableObject {
    static let defaultDurationSeconds = 30 * 60
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
    @Published private(set) var completionScoreReceipt: UserScore?
    @Published private(set) var completionContext: FocusCompletionContext?
    @Published var notice: String?

    private let focusService: FocusService
    private let userDefaults: UserDefaults
    private let savedStateKey = "pico.focus.saved-state.v3"
    private let legacySavedStateKey = "pico.focus.saved-state.v2"
    private var pendingBackgroundInterruptionTask: Task<Void, Never>?
    private var realtimeSubscription: FocusRealtimeSubscription?
    private var realtimeChannelID: String?
    private var isRealtimeRefreshing = false
    private var isDeviceLocking = false
    private var knownVillageResidentIDs: Set<UUID>?

    init(focusService: FocusService? = nil, userDefaults: UserDefaults = .standard) {
        self.focusService = focusService ?? FocusService()
        self.userDefaults = userDefaults
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
            resultSession = pendingResult.optimisticSession(from: savedState.session)
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
            let session = try await focusService.joinSession(invite.id, for: authSession)
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
            self.completionScoreReceipt = nil
            self.completionContext = nil
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

    func interruptCurrentSession(for authSession: AuthSession?) async {
        guard let authSession, let session = activeSession ?? liveSavedSession() else { return }
        await finish(
            session,
            pendingResult: .interrupt,
            authSession: authSession,
            preCompletionVillageResidentIDs: nil
        )
    }

    func leaveCurrentMultiplayerSession(for authSession: AuthSession?) async {
        guard
            let authSession,
            let session = lobbySession ?? activeSession,
            session.mode == .multiplayer,
            !isFinishing,
            !isCurrentUserHost(authSession)
        else {
            return
        }

        isFinishing = true
        notice = nil
        defer { isFinishing = false }

        do {
            _ = try await focusService.leaveSession(session.id, for: authSession)
            lobbySession = nil
            activeSession = nil
            sessionDetail = nil
            resultSession = nil
            completionScoreReceipt = nil
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
        resultSession = pendingResult.optimisticSession(from: savedState.session)
        completionScoreReceipt = nil
        hasPendingResultSync = true
        notice = nil
        isFinishing = true
        defer { isFinishing = false }

        do {
            let syncResult = try await sync(pendingResult, session: savedState.session, authSession: authSession)
            let optimisticSession = pendingResult.optimisticSession(from: savedState.session)
            resultSession = pendingResult.shouldUseSavedSession(syncResult.session, originalSession: savedState.session)
                ? syncResult.session
                : optimisticSession
            completionScoreReceipt = syncResult.score
            hasPendingResultSync = false
            clearSavedState()
            subscribeToRealtime(for: authSession, sessionID: nil)
            await loadIncomingInvites(for: authSession)
        } catch {
            guard !error.isCancellation else { return }
            hasPendingResultSync = true
            notice = "Result saved locally. It will retry when the app opens again."
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
            await self?.interruptCurrentSession(for: authSession)
        }
    }

    func resetResult() {
        guard !hasPendingResultSync else { return }
        resultSession = nil
        sessionDetail = nil
        completionContext = nil
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
            notice = nil
        case .launched, .live:
            lobbySession = nil
            activeSession = session
            resultSession = nil
            completionContext = nil
            notice = nil
        case .completed, .interrupted, .cancelled:
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
            notice = nil
            saveState(LocalFocusState(userID: authSession.user?.id ?? session.ownerID, session: session, pendingResult: nil))
        case .launched, .live:
            lobbySession = nil
            activeSession = session
            resultSession = nil
            completionContext = nil
            notice = nil
            saveState(LocalFocusState(userID: authSession.user?.id ?? session.ownerID, session: session, pendingResult: nil))
        case .completed, .interrupted, .cancelled:
            applyFinishedSession(session)
            clearSavedState()
        }
    }

    private func applyFinishedSession(_ session: FocusSession) {
        if session.status == .cancelled {
            clearFocusSessionState()
            return
        }

        lobbySession = nil
        activeSession = nil
        sessionDetail = nil
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
                applyOpenSession(detail.session, authSession: authSession)
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
                _ = await reconcileOpenSessions(for: authSession)
                await loadIncomingInvites(for: authSession)
                return
            }

            notice = displayMessage(for: error)
        }
    }

    private func syncOpenSessionState(for authSession: AuthSession) async {
        do {
            let detail = try await focusService.fetchCurrentSessionDetail(for: authSession)
            guard let detail, !detail.session.isFinished else {
                clearFocusSessionState()
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

    private func reconcileOpenSessions(for authSession: AuthSession) async -> FocusReconciliationResult? {
        do {
            return try await focusService.reconcileOpenSessions(for: authSession)
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
        preCompletionVillageResidentIDs: Set<UUID>?
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
        let optimisticSession = pendingResult.optimisticSession(from: session)
        lobbySession = nil
        activeSession = nil
        sessionDetail = nil
        resultSession = optimisticSession
        completionScoreReceipt = nil
        completionContext = capturedCompletionContext
        hasPendingResultSync = true
        saveState(LocalFocusState(
            userID: authSession.user?.id ?? session.ownerID,
            session: session,
            pendingResult: pendingResult
        ))

        do {
            let syncResult = try await sync(pendingResult, session: session, authSession: authSession)
            resultSession = pendingResult.shouldUseSavedSession(syncResult.session, originalSession: session)
                ? syncResult.session
                : optimisticSession
            completionScoreReceipt = syncResult.score
            hasPendingResultSync = false
            clearSavedState()
            subscribeToRealtime(for: authSession, sessionID: nil)
            await loadIncomingInvites(for: authSession)
        } catch {
            if !error.isCancellation {
                notice = "Result saved locally. It will retry when the app opens again."
            }
        }

        isFinishing = false
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
            let completion = try await focusService.completeSession(session.id, for: authSession)
            return FocusSyncResult(session: completion.session, score: completion.score)
        case .interrupt:
            let session = try await focusService.interruptSession(session.id, for: authSession)
            return FocusSyncResult(session: session, score: nil)
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
        userDefaults.removeObject(forKey: legacySavedStateKey)
    }

    private func loadSavedState() -> LocalFocusState? {
        if let data = userDefaults.data(forKey: savedStateKey),
           let savedState = try? JSONDecoder().decode(LocalFocusState.self, from: data) {
            return savedState
        }

        guard let data = userDefaults.data(forKey: legacySavedStateKey) else { return nil }
        return try? JSONDecoder().decode(LocalFocusState.self, from: data)
    }

    private func clearSavedState() {
        userDefaults.removeObject(forKey: savedStateKey)
        userDefaults.removeObject(forKey: legacySavedStateKey)
    }

    private func clearFocusSessionState() {
        pendingBackgroundInterruptionTask?.cancel()
        pendingBackgroundInterruptionTask = nil
        lobbySession = nil
        activeSession = nil
        resultSession = nil
        sessionDetail = nil
        hasPendingResultSync = false
        completionScoreReceipt = nil
        completionContext = nil
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
        completionScoreReceipt = nil
        completionContext = nil
        realtimeSubscription?.stop()
        realtimeSubscription = nil
        realtimeChannelID = nil
    }

    private func displayMessage(for error: Error) -> String? {
        guard !error.isCancellation else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
    let score: UserScore?
}

private struct LocalFocusState: Codable, Equatable {
    let userID: UUID
    let session: FocusSession
    let pendingResult: PendingFocusResult?
}

private enum PendingFocusResult: Codable, Equatable {
    case complete
    case interrupt

    private enum CodingKeys: String, CodingKey {
        case action
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
            self = .interrupt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .complete:
            try container.encode(Action.complete, forKey: .action)
        case .interrupt:
            try container.encode(Action.interrupt, forKey: .action)
        }
    }

    func optimisticSession(from session: FocusSession) -> FocusSession {
        switch self {
        case .complete:
            session.completed()
        case .interrupt:
            session.interrupted()
        }
    }
}
