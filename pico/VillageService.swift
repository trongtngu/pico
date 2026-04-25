//
//  VillageService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation

struct VillageResident: Identifiable, Equatable {
    var id: UUID { profile.userID }

    let profile: UserProfile
    let bondLevel: Int
    let completedPairSessions: Int
    let unlockedAt: Date?
}

enum VillageServiceError: LocalizedError {
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

final class VillageService {
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

    func fetchResidents(for authSession: AuthSession) async throws -> [VillageResident] {
        let response: [VillageResidentResponse] = try await send(
            path: "/rest/v1/rpc/list_village_residents",
            method: "POST",
            body: EmptyVillageRequest(),
            accessToken: authSession.accessToken
        )

        return response.map(\.villageResident)
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
            throw VillageServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw VillageServiceError.missingConfiguration
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
            throw VillageServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(VillageSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw VillageServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw VillageServiceError.invalidResponse
        }
    }
}

private struct EmptyVillageRequest: Encodable {}

private struct VillageResidentResponse: Decodable {
    let userId: UUID
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
    let bondLevel: Int
    let completedPairSessions: Int
    let unlockedAt: String

    var villageResident: VillageResident {
        VillageResident(
            profile: UserProfile(
                userID: userId,
                username: username,
                displayName: displayName,
                avatarConfig: avatarConfig
            ),
            bondLevel: bondLevel,
            completedPairSessions: completedPairSessions,
            unlockedAt: FocusDateFormatter.date(from: unlockedAt)
        )
    }
}

private struct VillageSupabaseErrorResponse: Decodable {
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
