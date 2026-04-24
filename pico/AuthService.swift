//
//  AuthService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser?

    #if DEBUG
    static let preview = AuthSession(
        accessToken: "preview-access-token",
        refreshToken: "preview-refresh-token",
        user: AuthUser.preview
    )
    #endif
}

struct AuthUser: Codable, Equatable {
    let id: UUID
    let email: String?

    #if DEBUG
    static let preview = AuthUser(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        email: "preview@example.com"
    )
    #endif
}

struct AuthResult: Equatable {
    let session: AuthSession?
    let message: String?
}

struct UserProfile: Equatable {
    let userID: UUID
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
}

enum AuthServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case missingProfile
    case usernameUnavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Add your Supabase project URL and anon key in SupabaseConfig.swift."
        case .invalidResponse:
            "Supabase returned a response the app could not read."
        case .missingProfile:
            "No public profile was found for this account."
        case .usernameUnavailable:
            "That username is already taken."
        case .requestFailed(let message):
            message
        }
    }
}

final class AuthService {
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

    func signUp(
        email: String,
        password: String,
        username: String,
        displayName: String,
        avatarConfig: AvatarConfig
    ) async throws -> AuthResult {
        let normalizedUsername = username.normalizedUsername
        guard try await isUsernameAvailable(normalizedUsername) else {
            throw AuthServiceError.usernameUnavailable
        }

        let response: SignUpResponse = try await send(
            path: "/auth/v1/signup",
            method: "POST",
            body: SignUpRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                data: SignUpMetadata(
                    username: normalizedUsername,
                    displayName: displayName.normalizedDisplayName,
                    avatarConfig: avatarConfig
                )
            )
        )

        if let accessToken = response.session?.accessToken ?? response.accessToken {
            return AuthResult(
                session: AuthSession(
                    accessToken: accessToken,
                    refreshToken: response.session?.refreshToken ?? response.refreshToken,
                    user: response.user ?? response.session?.user
                ),
                message: nil
            )
        }

        return AuthResult(
            session: nil,
            message: "Account created. Check your email to confirm your account before logging in."
        )
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        let response: SignInResponse = try await send(
            path: "/auth/v1/token?grant_type=password",
            method: "POST",
            body: AuthCredentials(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        )

        return AuthResult(
            session: AuthSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                user: response.user
            ),
            message: nil
        )
    }

    func fetchProfile(for authSession: AuthSession) async throws -> UserProfile {
        guard let userID = authSession.user?.id else {
            throw AuthServiceError.invalidResponse
        }

        let response: [UserProfileResponse] = try await send(
            path: "/rest/v1/user_profiles?select=user_id,username,display_name,avatar_config&user_id=eq.\(userID.uuidString)&limit=1",
            method: "GET",
            accessToken: authSession.accessToken
        )

        guard let profile = response.first else {
            throw AuthServiceError.missingProfile
        }

        return profile.userProfile
    }

    func updateProfile(
        displayName: String,
        avatarConfig: AvatarConfig,
        for authSession: AuthSession
    ) async throws -> UserProfile {
        guard let userID = authSession.user?.id else {
            throw AuthServiceError.invalidResponse
        }

        let response: [UserProfileResponse] = try await send(
            path: "/rest/v1/user_profiles?select=user_id,username,display_name,avatar_config&user_id=eq.\(userID.uuidString)",
            method: "PATCH",
            body: UserProfileUpdate(
                displayName: displayName.normalizedDisplayName,
                avatarConfig: avatarConfig
            ),
            accessToken: authSession.accessToken,
            headers: [
                "Prefer": "return=representation"
            ]
        )

        guard let profile = response.first else {
            throw AuthServiceError.invalidResponse
        }

        return profile.userProfile
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let response: [UsernameAvailabilityResponse] = try await send(
            path: "/rest/v1/user_profiles?select=username&username=eq.\(username)&limit=1",
            method: "GET",
            accessToken: SupabaseConfig.anonKey
        )

        return response.isEmpty
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        try await send(
            path: path,
            method: method,
            body: body,
            accessToken: SupabaseConfig.anonKey
        )
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        accessToken: String,
        headers: [String: String] = [:]
    ) async throws -> ResponseBody {
        let bodyData = try encoder.encode(body)
        return try await send(
            path: path,
            method: method,
            accessToken: accessToken,
            headers: headers,
            bodyData: bodyData
        )
    }

    private func send<ResponseBody: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        headers: [String: String] = [:]
    ) async throws -> ResponseBody {
        try await send(
            path: path,
            method: method,
            accessToken: accessToken,
            headers: headers,
            bodyData: nil
        )
    }

    private func send<ResponseBody: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        headers: [String: String],
        bodyData: Data?
    ) async throws -> ResponseBody {
        guard SupabaseConfig.isConfigured, let baseURL = SupabaseConfig.projectURL else {
            throw AuthServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AuthServiceError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(SupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw AuthServiceError.requestFailed(
                friendlyMessage(
                    from: errorResponse?.displayMessage
                        ?? responseBody
                        ?? "Supabase request failed with status \(httpResponse.statusCode)."
                )
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func friendlyMessage(from message: String) -> String {
        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("username") && lowercasedMessage.contains("duplicate") {
            return AuthServiceError.usernameUnavailable.errorDescription ?? message
        }

        return message
    }
}

private extension String {
    var normalizedUsername: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedDisplayName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AuthCredentials: Encodable {
    let email: String
    let password: String
}

private struct SignUpRequest: Encodable {
    let email: String
    let password: String
    let data: SignUpMetadata
}

private struct SignUpMetadata: Encodable {
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
}

private struct SignUpResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: AuthUser?
    let session: SessionPayload?
}

private struct SignInResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser?
}

private struct SessionPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser?
}

private struct UserProfileResponse: Decodable {
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

private struct UserProfileUpdate: Encodable {
    let displayName: String
    let avatarConfig: AvatarConfig
}

private struct UsernameAvailabilityResponse: Decodable {
    let username: String
}

private struct SupabaseErrorResponse: Decodable {
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
