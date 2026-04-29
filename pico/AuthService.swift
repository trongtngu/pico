//
//  AuthService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Security
import Supabase

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser?
    let expiresAt: Date?

    init(accessToken: String, refreshToken: String?, user: AuthUser?, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
        self.expiresAt = expiresAt
    }

    init(supabaseSession: Session) {
        self.init(
            accessToken: supabaseSession.accessToken,
            refreshToken: supabaseSession.refreshToken,
            user: AuthUser(supabaseUser: supabaseSession.user),
            expiresAt: Date(timeIntervalSince1970: supabaseSession.expiresAt)
        )
    }

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

    init(id: UUID, email: String?) {
        self.id = id
        self.email = email
    }

    init(supabaseUser: User) {
        self.init(id: supabaseUser.id, email: supabaseUser.email)
    }

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
    private let client: SupabaseClient?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        if SupabaseConfig.isConfigured, let projectURL = SupabaseConfig.projectURL {
            client = SupabaseClient(
                supabaseURL: projectURL,
                supabaseKey: SupabaseConfig.anonKey,
                options: SupabaseClientOptions(
                    auth: .init(autoRefreshToken: true)
                )
            )
        } else {
            client = nil
        }

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

        guard let client else {
            throw AuthServiceError.missingConfiguration
        }

        do {
            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                data: [
                    "username": .string(normalizedUsername),
                    "display_name": .string(displayName.normalizedDisplayName),
                    "avatar_config": .object(avatarConfig.supabaseMetadataJSON),
                    "time_zone": .string(TimeZone.current.identifier)
                ]
            )

            guard let session = response.session else {
                return AuthResult(
                    session: nil,
                    message: "Account created. Check your email to confirm your account before logging in."
                )
            }

            return AuthResult(
                session: AuthSession(supabaseSession: session),
                message: nil
            )
        } catch {
            throw AuthServiceError.requestFailed(friendlyMessage(from: error))
        }
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        guard let client else {
            throw AuthServiceError.missingConfiguration
        }

        do {
            let session = try await client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            return AuthResult(session: AuthSession(supabaseSession: session), message: nil)
        } catch {
            throw AuthServiceError.requestFailed(friendlyMessage(from: error))
        }
    }

    func restoreSession() async throws -> AuthSession? {
        guard let client else {
            throw AuthServiceError.missingConfiguration
        }

        do {
            return try await AuthSession(supabaseSession: client.auth.session)
        } catch AuthError.sessionMissing {
            do {
                return try await migrateLegacySessionIfNeeded(using: client)
            } catch {
                throw AuthServiceError.requestFailed(friendlyMessage(from: error))
            }
        } catch {
            throw AuthServiceError.requestFailed(friendlyMessage(from: error))
        }
    }

    func validSession() async throws -> AuthSession? {
        try await restoreSession()
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut()
    }

    func authSessionChanges() -> AsyncStream<AuthSession?> {
        guard let client else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let task = Task {
                for await change in client.auth.authStateChanges {
                    continuation.yield(change.session.map(AuthSession.init(supabaseSession:)))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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

    func syncUserTimezone(for authSession: AuthSession) async throws {
        let _: String = try await send(
            path: "/rest/v1/rpc/set_user_timezone",
            method: "POST",
            body: UserTimezoneUpdate(timeZone: TimeZone.current.identifier),
            accessToken: authSession.accessToken
        )
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

    private func friendlyMessage(from error: Error) -> String {
        friendlyMessage(from: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    private func migrateLegacySessionIfNeeded(using client: SupabaseClient) async throws -> AuthSession? {
        let legacyStorage = LegacyAuthSessionStorage()
        guard let legacySession = legacyStorage.loadSession() else { return nil }
        guard let refreshToken = legacySession.refreshToken else {
            legacyStorage.deleteSession()
            return nil
        }

        do {
            let session = try await client.auth.setSession(
                accessToken: legacySession.accessToken,
                refreshToken: refreshToken
            )
            legacyStorage.deleteSession()
            return AuthSession(supabaseSession: session)
        } catch {
            legacyStorage.deleteSession()
            throw error
        }
    }
}

private extension AvatarConfig {
    var supabaseMetadataJSON: [String: AnyJSON] {
        [
            "version": .integer(version),
            "character": .string(character),
            "hat": .integer(hat)
        ]
    }
}

private final class LegacyAuthSessionStorage {
    private let service = "\(Bundle.main.bundleIdentifier ?? "trongpapaya.pico").auth-session"
    private let account = "supabase-session"

    func loadSession() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func deleteSession() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
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

private struct UserTimezoneUpdate: Encodable {
    let timeZone: String
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
