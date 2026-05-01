//
//  FishService.swift
//  pico
//
//  Created by Codex on 1/5/2026.
//

import Foundation

enum FishType: String, CaseIterable, Codable, Equatable, Hashable {
    case bass
    case salmon
    case tuna

    var displayName: String {
        switch self {
        case .bass:
            "Bass"
        case .salmon:
            "Salmon"
        case .tuna:
            "Tuna"
        }
    }

    var sellValue: Int {
        switch self {
        case .bass:
            1
        case .salmon:
            2
        case .tuna:
            3
        }
    }
}

enum FishRarity: String, Codable, Equatable, Hashable {
    case common
    case uncommon
    case rare

    var label: String {
        rawValue
    }
}

struct FishCatch: Identifiable, Equatable {
    let id: UUID
    let userID: UUID?
    let sessionID: UUID
    let catchIndex: Int?
    let fishType: FishType
    let rarity: FishRarity
    let sellValue: Int
    let caughtAt: Date?
    let soldAt: Date?
    let soldForBerries: Int?

    var displayName: String {
        fishType.displayName
    }

    var rarityLabel: String {
        rarity.label
    }

    var isSold: Bool {
        soldAt != nil
    }

    func sold(at date: Date = Date()) -> FishCatch {
        FishCatch(
            id: id,
            userID: userID,
            sessionID: sessionID,
            catchIndex: catchIndex,
            fishType: fishType,
            rarity: rarity,
            sellValue: sellValue,
            caughtAt: caughtAt,
            soldAt: date,
            soldForBerries: sellValue
        )
    }
}

struct FishCatchSummary: Equatable {
    let bassCount: Int
    let salmonCount: Int
    let tunaCount: Int
    let totalPotentialSellValue: Int
    let catchCount: Int

    var hasCatches: Bool {
        catchCount > 0
    }

    static let empty = FishCatchSummary(
        bassCount: 0,
        salmonCount: 0,
        tunaCount: 0,
        totalPotentialSellValue: 0,
        catchCount: 0
    )

    static func catches(_ catches: [FishCatch]) -> FishCatchSummary {
        FishCatchSummary(
            bassCount: catches.filter { $0.fishType == .bass }.count,
            salmonCount: catches.filter { $0.fishType == .salmon }.count,
            tunaCount: catches.filter { $0.fishType == .tuna }.count,
            totalPotentialSellValue: catches.reduce(0) { $0 + $1.sellValue },
            catchCount: catches.count
        )
    }
}

struct FishSaleResult: Equatable {
    let balance: UserBerryBalance
    let soldFishCount: Int
    let soldBerryAmount: Int
    let soldBass: Int
    let soldSalmon: Int
    let soldTuna: Int
}

enum FishServiceError: LocalizedError {
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

final class FishService {
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

    func fetchSessionCatches(sessionID: UUID, for authSession: AuthSession) async throws -> [FishCatch] {
        try await fetchFishCatches(
            path: "/rest/v1/user_fish_catches?select=id,user_id,session_id,catch_index,fish_type,rarity,sell_value,caught_at,sold_at,sold_for_berries&session_id=eq.\(sessionID.uuidString)&order=catch_index.asc,caught_at.asc",
            accessToken: authSession.accessToken
        )
    }

    func fetchInventory(for authSession: AuthSession) async throws -> [FishCatch] {
        try await fetchFishCatches(
            path: "/rest/v1/user_fish_catches?select=id,user_id,session_id,catch_index,fish_type,rarity,sell_value,caught_at,sold_at,sold_for_berries&sold_at=is.null&order=caught_at.desc",
            accessToken: authSession.accessToken
        )
    }

    func sellFish(catchIDs: [UUID], for authSession: AuthSession) async throws -> FishSaleResult {
        let response: [FishSaleResponse] = try await send(
            path: "/rest/v1/rpc/sell_user_fish",
            method: "POST",
            body: FishSaleRequest(catchIds: catchIDs),
            accessToken: authSession.accessToken
        )

        guard let result = response.first else {
            throw FishServiceError.invalidResponse
        }

        return result.saleResult
    }

    private func fetchFishCatches(path: String, accessToken: String) async throws -> [FishCatch] {
        let response: [FishCatchResponse] = try await send(
            path: path,
            method: "GET",
            accessToken: accessToken
        )

        return response.map(\.fishCatch)
    }

    private func send<ResponseBody: Decodable>(
        path: String,
        method: String,
        accessToken: String
    ) async throws -> ResponseBody {
        try await send(
            path: path,
            method: method,
            accessToken: accessToken,
            bodyData: nil
        )
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
            throw FishServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw FishServiceError.missingConfiguration
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
            throw FishServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(FishSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw FishServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw FishServiceError.invalidResponse
        }
    }
}

private struct FishCatchResponse: Decodable {
    let id: UUID
    let userId: UUID?
    let sessionId: UUID
    let catchIndex: Int?
    let fishType: FishType
    let rarity: FishRarity
    let sellValue: Int
    let caughtAt: String?
    let soldAt: String?
    let soldForBerries: Int?

    var fishCatch: FishCatch {
        FishCatch(
            id: id,
            userID: userId,
            sessionID: sessionId,
            catchIndex: catchIndex,
            fishType: fishType,
            rarity: rarity,
            sellValue: sellValue,
            caughtAt: caughtAt.flatMap(FocusDateFormatter.date(from:)),
            soldAt: soldAt.flatMap(FocusDateFormatter.date(from:)),
            soldForBerries: soldForBerries
        )
    }
}

private struct FishSaleRequest: Encodable {
    let catchIds: [UUID]
}

private struct FishSaleResponse: Decodable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: String?
    let soldFishCount: Int
    let soldBerryAmount: Int
    let soldBass: Int
    let soldSalmon: Int
    let soldTuna: Int

    var saleResult: FishSaleResult {
        FishSaleResult(
            balance: UserBerryBalance(
                berries: berries,
                completionStreak: completionStreak,
                lastCompletedOn: lastCompletedOn,
                lastCompletedAt: lastCompletedAt.flatMap(FocusDateFormatter.date(from:))
            ),
            soldFishCount: soldFishCount,
            soldBerryAmount: soldBerryAmount,
            soldBass: soldBass,
            soldSalmon: soldSalmon,
            soldTuna: soldTuna
        )
    }
}

private struct FishSupabaseErrorResponse: Decodable {
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
