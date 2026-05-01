//
//  BerryService.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import Foundation

struct UserBerryBalance: Equatable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: Date?

    static let zero = UserBerryBalance(
        berries: 0,
        completionStreak: 0,
        lastCompletedOn: nil,
        lastCompletedAt: nil
    )
}

enum BerryServiceError: LocalizedError {
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

final class BerryService {
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

    func fetchUserBerryBalance(for authSession: AuthSession) async throws -> UserBerryBalance {
        let response: [UserBerryBalanceResponse] = try await send(
            path: "/rest/v1/rpc/fetch_user_berries",
            method: "POST",
            body: EmptyBerryRequest(),
            accessToken: authSession.accessToken
        )

        return response.first?.berryBalance ?? .zero
    }

    func purchaseAvatarHat(_ hat: AvatarHat, for authSession: AuthSession) async throws -> HatPurchaseResult {
        let response: [HatPurchaseResponse] = try await send(
            path: "/rest/v1/rpc/purchase_avatar_hat",
            method: "POST",
            body: HatPurchaseRequest(hat: hat.rawValue),
            accessToken: authSession.accessToken
        )

        guard let result = response.first else {
            throw BerryServiceError.invalidResponse
        }

        return result.purchaseResult
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
            throw BerryServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw BerryServiceError.missingConfiguration
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
            throw BerryServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(BerrySupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw BerryServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw BerryServiceError.invalidResponse
        }
    }
}

private struct EmptyBerryRequest: Encodable {}

struct HatPurchaseResult: Equatable {
    let balance: UserBerryBalance
    let ownedHats: Set<AvatarHat>
}

private struct HatPurchaseRequest: Encodable {
    let hat: Int
}

private struct UserBerryBalanceResponse: Decodable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: String?

    var berryBalance: UserBerryBalance {
        UserBerryBalance(
            berries: berries,
            completionStreak: completionStreak,
            lastCompletedOn: lastCompletedOn,
            lastCompletedAt: lastCompletedAt.flatMap(FocusDateFormatter.date(from:))
        )
    }
}

private struct HatPurchaseResponse: Decodable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: String?
    let ownedHats: [Int]

    var purchaseResult: HatPurchaseResult {
        HatPurchaseResult(
            balance: UserBerryBalance(
                berries: berries,
                completionStreak: completionStreak,
                lastCompletedOn: lastCompletedOn,
                lastCompletedAt: lastCompletedAt.flatMap(FocusDateFormatter.date(from:))
            ),
            ownedHats: Set(ownedHats.compactMap(AvatarHat.init(rawValue:))).union([.none])
        )
    }
}

private struct BerrySupabaseErrorResponse: Decodable {
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
