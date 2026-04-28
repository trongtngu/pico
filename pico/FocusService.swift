//
//  FocusService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation

enum FocusSessionMode: String, Codable, Equatable {
    case solo
    case multiplayer
}

enum FocusSessionStatus: String, Codable, Equatable {
    case lobby
    case live
    case interrupted
    case completed
    case cancelled
}

enum FocusSessionEventType: String, Codable, Equatable {
    case memberJoined = "member_joined"
    case sessionStarted = "session_started"
    case memberInterrupted = "member_interrupted"
    case memberCompleted = "member_completed"
}

enum FocusSessionMemberRole: String, Codable, Equatable {
    case host
    case participant
}

enum FocusSessionMemberStatus: String, Codable, Equatable {
    case invited
    case joined
    case left
}

struct FocusSession: Identifiable, Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let mode: FocusSessionMode
    let status: FocusSessionStatus
    let durationSeconds: Int
    let startedAt: Date?
    let plannedEndAt: Date?
    let endedAt: Date?

    var isLobby: Bool {
        status == .lobby
    }

    var isLive: Bool {
        status == .live
    }

    var isFinished: Bool {
        status == .completed || status == .interrupted || status == .cancelled
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        guard let plannedEndAt else { return durationSeconds }
        return max(0, Int(ceil(plannedEndAt.timeIntervalSince(date))))
    }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        guard let startedAt else { return 0 }
        let endDate = endedAt ?? plannedEndAt.map { min(date, $0) } ?? date
        return max(0, Int(endDate.timeIntervalSince(startedAt)))
    }

    func completed(at date: Date = Date()) -> FocusSession {
        FocusSession(
            id: id,
            ownerID: ownerID,
            mode: mode,
            status: .completed,
            durationSeconds: durationSeconds,
            startedAt: startedAt,
            plannedEndAt: plannedEndAt,
            endedAt: max(date, plannedEndAt ?? date)
        )
    }

    func interrupted(at date: Date = Date()) -> FocusSession {
        FocusSession(
            id: id,
            ownerID: ownerID,
            mode: mode,
            status: .interrupted,
            durationSeconds: durationSeconds,
            startedAt: startedAt,
            plannedEndAt: plannedEndAt,
            endedAt: date
        )
    }
}

struct FocusCompletionResult: Equatable {
    let session: FocusSession
    let score: UserScore
}

struct FocusSessionMember: Identifiable, Equatable {
    var id: UUID { userID }

    let userID: UUID
    let role: FocusSessionMemberRole
    let status: FocusSessionMemberStatus
    let profile: UserProfile
    let isCompleted: Bool
    let isInterrupted: Bool
}

struct FocusSessionDetail: Equatable {
    let session: FocusSession
    let host: UserProfile
    let members: [FocusSessionMember]

    func member(for userID: UUID?) -> FocusSessionMember? {
        guard let userID else { return nil }
        return members.first { $0.userID == userID }
    }

    func isHost(_ userID: UUID?) -> Bool {
        member(for: userID)?.role == .host
    }
}

struct FocusSessionInvite: Identifiable, Equatable {
    var id: UUID { session.id }

    let session: FocusSession
    let host: UserProfile
    let createdAt: Date?
}

struct FocusReconciliationResult: Equatable {
    let completedSessions: Int
    let cancelledLobbies: Int
    let leftLobbies: Int

    var changedOpenSessionState: Bool {
        completedSessions > 0 || cancelledLobbies > 0 || leftLobbies > 0
    }
}

enum FocusServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Add your Supabase project URL and anon key in SupabaseConfig.swift."
        case .invalidResponse:
            "Supabase returned a response the app could not read."
        case .requestFailed(let message):
            message
        }
    }
}

final class FocusService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func createSession(
        mode: FocusSessionMode,
        durationSeconds: Int,
        for authSession: AuthSession
    ) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/create_focus_session",
            body: CreateFocusSessionRequest(
                sessionMode: mode.rawValue,
                durationSeconds: durationSeconds
            ),
            accessToken: authSession.accessToken
        )
    }

    func updateSessionConfig(
        _ id: UUID,
        durationSeconds: Int,
        for authSession: AuthSession
    ) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/update_focus_session_config",
            body: UpdateFocusSessionConfigRequest(
                targetSessionId: id,
                durationSeconds: durationSeconds
            ),
            accessToken: authSession.accessToken
        )
    }

    func inviteMembers(
        _ userIDs: [UUID],
        to id: UUID,
        for authSession: AuthSession
    ) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/invite_focus_session_members",
            body: InviteFocusSessionMembersRequest(
                targetSessionId: id,
                inviteeIds: userIDs
            ),
            accessToken: authSession.accessToken
        )
    }

    func fetchSessionDetail(_ id: UUID, for authSession: AuthSession) async throws -> FocusSessionDetail {
        let response: FocusSessionDetailResponse = try await send(
            path: "/rest/v1/rpc/fetch_focus_session_detail",
            method: "POST",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )

        guard let detail = response.focusSessionDetail else {
            throw FocusServiceError.invalidResponse
        }

        return detail
    }

    func fetchIncomingInvites(for authSession: AuthSession) async throws -> [FocusSessionInvite] {
        let response: [FocusSessionInviteResponse] = try await send(
            path: "/rest/v1/rpc/list_incoming_focus_session_invites",
            method: "POST",
            body: EmptyFocusRequest(),
            accessToken: authSession.accessToken
        )

        return response.compactMap(\.focusSessionInvite)
    }

    func reconcileOpenSessions(for authSession: AuthSession) async throws -> FocusReconciliationResult {
        let response: ReconcileOpenFocusSessionsResponse = try await send(
            path: "/rest/v1/rpc/reconcile_open_focus_sessions",
            method: "POST",
            body: EmptyFocusRequest(),
            accessToken: authSession.accessToken
        )

        return response.focusReconciliationResult
    }

    func joinSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/join_focus_session",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    func declineSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/decline_focus_session",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    func leaveSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/leave_focus_session",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    func startSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/start_focus_session",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    func completeSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusCompletionResult {
        let response: FocusCompletionResponse = try await send(
            path: "/rest/v1/rpc/complete_focus_session_with_score",
            method: "POST",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )

        guard let result = response.focusCompletionResult else {
            throw FocusServiceError.invalidResponse
        }

        return result
    }

    func cancelSessionLobby(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/cancel_session_lobby",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    func interruptSession(_ id: UUID, for authSession: AuthSession) async throws -> FocusSession {
        try await sessionResponse(
            path: "/rest/v1/rpc/interrupt_focus_session",
            body: FocusSessionIDRequest(targetSessionId: id),
            accessToken: authSession.accessToken
        )
    }

    private func sessionResponse<RequestBody: Encodable>(
        path: String,
        body: RequestBody,
        accessToken: String
    ) async throws -> FocusSession {
        let response: FocusSessionResponse = try await send(
            path: path,
            method: "POST",
            body: body,
            accessToken: accessToken
        )

        guard let session = response.focusSession else {
            throw FocusServiceError.invalidResponse
        }

        return session
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        accessToken: String
    ) async throws -> ResponseBody {
        let bodyData = try encoder.encode(body)
        return try await send(
            path: path,
            method: method,
            accessToken: accessToken,
            bodyData: bodyData
        )
    }

    private func send<ResponseBody: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        bodyData: Data?
    ) async throws -> ResponseBody {
        guard SupabaseConfig.isConfigured, let baseURL = SupabaseConfig.projectURL else {
            throw FocusServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw FocusServiceError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FocusServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(FocusSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw FocusServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw FocusServiceError.invalidResponse
        }
    }
}

enum FocusDateFormatter {
    nonisolated static func date(from string: String) -> Date? {
        makeFormatter(formatOptions: [.withInternetDateTime, .withFractionalSeconds]).date(from: string)
            ?? makeFormatter(formatOptions: [.withInternetDateTime]).date(from: string)
    }

    nonisolated static func string(from date: Date) -> String {
        makeFormatter(formatOptions: [.withInternetDateTime, .withFractionalSeconds]).string(from: date)
    }

    private nonisolated static func makeFormatter(formatOptions: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        return formatter
    }
}

private struct CreateFocusSessionRequest: Encodable {
    let sessionMode: String
    let durationSeconds: Int
}

private struct UpdateFocusSessionConfigRequest: Encodable {
    let targetSessionId: UUID
    let durationSeconds: Int
}

private struct InviteFocusSessionMembersRequest: Encodable {
    let targetSessionId: UUID
    let inviteeIds: [UUID]
}

private struct FocusSessionIDRequest: Encodable {
    let targetSessionId: UUID
}

private struct EmptyFocusRequest: Encodable {}

private struct ReconcileOpenFocusSessionsResponse: Decodable {
    let completedSessions: Int
    let cancelledLobbies: Int
    let leftLobbies: Int

    var focusReconciliationResult: FocusReconciliationResult {
        FocusReconciliationResult(
            completedSessions: completedSessions,
            cancelledLobbies: cancelledLobbies,
            leftLobbies: leftLobbies
        )
    }
}

private struct FocusSessionResponse: Decodable, Equatable {
    let id: UUID
    let ownerId: UUID
    let mode: FocusSessionMode
    let status: FocusSessionStatus
    let durationSeconds: Int
    let startedAt: String?
    let plannedEndAt: String?
    let endedAt: String?

    var focusSession: FocusSession? {
        FocusSession(
            id: id,
            ownerID: ownerId,
            mode: mode,
            status: status,
            durationSeconds: durationSeconds,
            startedAt: startedAt.flatMap(FocusDateFormatter.date(from:)),
            plannedEndAt: plannedEndAt.flatMap(FocusDateFormatter.date(from:)),
            endedAt: endedAt.flatMap(FocusDateFormatter.date(from:))
        )
    }
}

private struct FocusCompletionResponse: Decodable {
    let session: FocusSessionResponse
    let score: FocusUserScoreResponse

    var focusCompletionResult: FocusCompletionResult? {
        guard let focusSession = session.focusSession else { return nil }
        return FocusCompletionResult(
            session: focusSession,
            score: score.userScore
        )
    }
}

private struct FocusUserScoreResponse: Decodable {
    let score: Int
    let currentStreak: Int
    let lastScoredOn: String?
    let lastScoredAt: String?

    var userScore: UserScore {
        UserScore(
            score: score,
            currentStreak: currentStreak,
            lastScoredOn: lastScoredOn,
            lastScoredAt: lastScoredAt.flatMap(FocusDateFormatter.date(from:))
        )
    }
}

private struct FocusSessionDetailResponse: Decodable {
    let session: FocusSessionResponse
    let host: FocusUserProfileResponse
    let members: [FocusSessionMemberResponse]

    var focusSessionDetail: FocusSessionDetail? {
        guard let focusSession = session.focusSession else { return nil }
        return FocusSessionDetail(
            session: focusSession,
            host: host.userProfile,
            members: members.map(\.focusSessionMember)
        )
    }
}

private struct FocusSessionMemberResponse: Decodable {
    let userId: UUID
    let role: FocusSessionMemberRole
    let status: FocusSessionMemberStatus
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
    let isCompleted: Bool
    let isInterrupted: Bool

    var focusSessionMember: FocusSessionMember {
        FocusSessionMember(
            userID: userId,
            role: role,
            status: status,
            profile: UserProfile(
                userID: userId,
                username: username,
                displayName: displayName,
                avatarConfig: avatarConfig
            ),
            isCompleted: isCompleted,
            isInterrupted: isInterrupted
        )
    }
}

private struct FocusUserProfileResponse: Decodable {
    let userId: UUID
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig

    var userProfile: UserProfile {
        UserProfile(
            userID: userId,
            username: username,
            displayName: displayName,
            avatarConfig: avatarConfig
        )
    }
}

private struct FocusSessionInviteResponse: Decodable {
    let id: UUID
    let ownerId: UUID
    let mode: FocusSessionMode
    let status: FocusSessionStatus
    let durationSeconds: Int
    let startedAt: String?
    let plannedEndAt: String?
    let endedAt: String?
    let createdAt: String
    let hostUserId: UUID
    let hostUsername: String
    let hostDisplayName: String
    let hostAvatarConfig: AvatarConfig

    var focusSessionInvite: FocusSessionInvite? {
        guard let session = FocusSessionResponse(
            id: id,
            ownerId: ownerId,
            mode: mode,
            status: status,
            durationSeconds: durationSeconds,
            startedAt: startedAt,
            plannedEndAt: plannedEndAt,
            endedAt: endedAt
        ).focusSession else {
            return nil
        }

        return FocusSessionInvite(
            session: session,
            host: UserProfile(
                userID: hostUserId,
                username: hostUsername,
                displayName: hostDisplayName,
                avatarConfig: hostAvatarConfig
            ),
            createdAt: FocusDateFormatter.date(from: createdAt)
        )
    }
}

private struct FocusSupabaseErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
    let errorCode: String?

    var displayMessage: String? {
        let mainMessage = message ?? msg ?? errorDescription ?? error

        if let mainMessage, let errorCode {
            return "\(mainMessage) (\(errorCode))"
        }

        return mainMessage
    }
}
