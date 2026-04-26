//
//  ScoreService.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import Foundation

struct UserScore: Equatable {
    let score: Int
    let currentStreak: Int
    let lastScoredOn: String?
    let lastScoredAt: Date?

    static let zero = UserScore(
        score: 0,
        currentStreak: 0,
        lastScoredOn: nil,
        lastScoredAt: nil
    )
}

enum ScoreServiceError: LocalizedError {
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

final class ScoreService {
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

    func fetchUserScore(for authSession: AuthSession) async throws -> UserScore {
        let response: [UserScoreResponse] = try await send(
            path: "/rest/v1/rpc/fetch_user_score",
            method: "POST",
            body: EmptyScoreRequest(),
            accessToken: authSession.accessToken
        )

        return response.first?.userScore ?? .zero
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
            throw ScoreServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ScoreServiceError.missingConfiguration
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
            throw ScoreServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(ScoreSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw ScoreServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw ScoreServiceError.invalidResponse
        }
    }
}

private struct EmptyScoreRequest: Encodable {}

private struct UserScoreResponse: Decodable {
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

private struct ScoreSupabaseErrorResponse: Decodable {
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
