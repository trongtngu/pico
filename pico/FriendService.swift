//
//  FriendService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation

struct FriendRequest: Identifiable, Equatable {
    let id: UUID
    let requester: UserProfile
    let createdAt: String
}

enum FriendServiceError: LocalizedError {
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

final class FriendService {
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

    func findProfile(username: String, for authSession: AuthSession) async throws -> UserProfile? {
        let response: [FriendUserProfileResponse] = try await send(
            path: "/rest/v1/user_profiles?select=user_id,username,display_name,avatar_config&username=eq.\(username)&limit=1",
            method: "GET",
            accessToken: authSession.accessToken
        )

        return response.first?.userProfile
    }

    func searchProfiles(matching query: String, for authSession: AuthSession) async throws -> [UserProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedCharacters = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "_-"))
        let searchTerm = normalizedQuery.unicodeScalars.reduce(into: "") { result, scalar in
            guard allowedCharacters.contains(scalar) else { return }
            result.unicodeScalars.append(scalar)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerm.isEmpty else { return [] }

        let pattern = "*\(searchTerm)*"
        let response: [FriendUserProfileResponse] = try await send(
            path: "/rest/v1/user_profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,username,display_name,avatar_config"),
                URLQueryItem(name: "or", value: "(username.ilike.\(pattern),display_name.ilike.\(pattern))"),
                URLQueryItem(name: "order", value: "display_name.asc,username.asc"),
                URLQueryItem(name: "limit", value: "20")
            ],
            accessToken: authSession.accessToken,
            bodyData: nil
        )

        return response.map(\.userProfile)
    }

    func sendFriendRequest(to username: String, for authSession: AuthSession) async throws {
        let _: FriendRPCResponse = try await send(
            path: "/rest/v1/rpc/send_friend_request",
            method: "POST",
            body: SendFriendRequest(recipientUsername: username),
            accessToken: authSession.accessToken
        )
    }

    func fetchIncomingRequests(for authSession: AuthSession) async throws -> [FriendRequest] {
        let response: [IncomingFriendRequestResponse] = try await send(
            path: "/rest/v1/rpc/list_incoming_friend_requests",
            method: "POST",
            body: EmptyRequest(),
            accessToken: authSession.accessToken
        )

        return response.map(\.friendRequest)
    }

    func acceptFriendRequest(_ id: UUID, for authSession: AuthSession) async throws {
        let _: FriendRPCResponse = try await send(
            path: "/rest/v1/rpc/accept_friend_request",
            method: "POST",
            body: FriendRequestAction(requestId: id),
            accessToken: authSession.accessToken
        )
    }

    func rejectFriendRequest(_ id: UUID, for authSession: AuthSession) async throws {
        let _: FriendRPCResponse = try await send(
            path: "/rest/v1/rpc/reject_friend_request",
            method: "POST",
            body: FriendRequestAction(requestId: id),
            accessToken: authSession.accessToken
        )
    }

    func fetchFriends(for authSession: AuthSession) async throws -> [UserProfile] {
        let response: [FriendUserProfileResponse] = try await send(
            path: "/rest/v1/rpc/list_friends",
            method: "POST",
            body: EmptyRequest(),
            accessToken: authSession.accessToken
        )

        return response.map(\.userProfile)
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
        accessToken: String
    ) async throws -> ResponseBody {
        try await send(
            path: path,
            method: method,
            queryItems: nil,
            accessToken: accessToken,
            bodyData: nil
        )
    }

    private func send<ResponseBody: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        accessToken: String,
        bodyData: Data?
    ) async throws -> ResponseBody {
        guard SupabaseConfig.isConfigured, let baseURL = SupabaseConfig.projectURL else {
            throw FriendServiceError.missingConfiguration
        }

        guard let baseRequestURL = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw FriendServiceError.missingConfiguration
        }

        var url = baseRequestURL
        if let queryItems {
            guard var components = URLComponents(url: baseRequestURL, resolvingAgainstBaseURL: false) else {
                throw FriendServiceError.missingConfiguration
            }
            components.queryItems = queryItems

            guard let componentURL = components.url else {
                throw FriendServiceError.missingConfiguration
            }
            url = componentURL
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
            throw FriendServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(FriendSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw FriendServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw FriendServiceError.invalidResponse
        }
    }
}

private struct EmptyRequest: Encodable {}

private struct SendFriendRequest: Encodable {
    let recipientUsername: String
}

private struct FriendRequestAction: Encodable {
    let requestId: UUID
}

private struct FriendRPCResponse: Decodable {
    let id: UUID
}

private struct FriendUserProfileResponse: Decodable {
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

private struct IncomingFriendRequestResponse: Decodable {
    let id: UUID
    let requesterId: UUID
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
    let createdAt: String

    var friendRequest: FriendRequest {
        FriendRequest(
            id: id,
            requester: UserProfile(
                userID: requesterId,
                username: username,
                displayName: displayName,
                avatarConfig: avatarConfig
            ),
            createdAt: createdAt
        )
    }
}

private struct FriendSupabaseErrorResponse: Decodable {
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
