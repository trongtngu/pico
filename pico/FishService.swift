//
//  FishService.swift
//  pico
//
//  Created by Codex on 1/5/2026.
//

import Foundation

struct FishID: RawRepresentable, Codable, Equatable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let bass = FishID(rawValue: "bass")
    static let salmon = FishID(rawValue: "salmon")
    static let tuna = FishID(rawValue: "tuna")

    var displayName: String {
        rawValue.split(separator: "_")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    var sellValue: Int {
        1
    }

    var assetName: String {
        rawValue
    }
}

typealias FishType = FishID

enum FishRarity: String, Codable, Equatable, Hashable {
    case common
    case rare
    case ultraRare = "ultra_rare"

    var label: String {
        switch self {
        case .common:
            "common"
        case .rare:
            "rare"
        case .ultraRare:
            "ultra rare"
        }
    }
}

struct FishCatch: Identifiable, Equatable {
    let id: UUID
    let userID: UUID?
    let sessionID: UUID
    let catchIndex: Int?
    let seaCritterID: FishID
    let rarity: FishRarity
    let sellValue: Int
    let caughtAt: Date?
    let soldAt: Date?
    let soldForBerries: Int?

    var fishType: FishType {
        seaCritterID
    }

    var displayName: String {
        seaCritterID.displayName
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
            seaCritterID: seaCritterID,
            rarity: rarity,
            sellValue: sellValue,
            caughtAt: caughtAt,
            soldAt: date,
            soldForBerries: sellValue
        )
    }

    init(
        id: UUID,
        userID: UUID?,
        sessionID: UUID,
        catchIndex: Int?,
        seaCritterID: FishID,
        rarity: FishRarity,
        sellValue: Int,
        caughtAt: Date?,
        soldAt: Date?,
        soldForBerries: Int?
    ) {
        self.id = id
        self.userID = userID
        self.sessionID = sessionID
        self.catchIndex = catchIndex
        self.seaCritterID = seaCritterID
        self.rarity = rarity
        self.sellValue = sellValue
        self.caughtAt = caughtAt
        self.soldAt = soldAt
        self.soldForBerries = soldForBerries
    }

    init(
        id: UUID,
        userID: UUID?,
        sessionID: UUID,
        catchIndex: Int?,
        fishType: FishType,
        rarity: FishRarity,
        sellValue: Int,
        caughtAt: Date?,
        soldAt: Date?,
        soldForBerries: Int?
    ) {
        self.init(
            id: id,
            userID: userID,
            sessionID: sessionID,
            catchIndex: catchIndex,
            seaCritterID: fishType,
            rarity: rarity,
            sellValue: sellValue,
            caughtAt: caughtAt,
            soldAt: soldAt,
            soldForBerries: soldForBerries
        )
    }
}

struct FishCatchSummary: Equatable {
    let countsByCritterID: [FishID: Int]
    let totalPotentialSellValue: Int
    let catchCount: Int

    var hasCatches: Bool {
        catchCount > 0
    }

    static let empty = FishCatchSummary(
        countsByCritterID: [:],
        totalPotentialSellValue: 0,
        catchCount: 0
    )

    static func catches(_ catches: [FishCatch]) -> FishCatchSummary {
        FishCatchSummary(
            countsByCritterID: Dictionary(grouping: catches, by: \.seaCritterID)
                .mapValues(\.count),
            totalPotentialSellValue: catches.reduce(0) { $0 + $1.sellValue },
            catchCount: catches.count
        )
    }
}

struct FishCatalogItem: Identifiable, Equatable {
    let id: FishID
    let displayName: String
    let rarity: FishRarity
    let sellValue: Int
    let assetName: String
    let sortOrder: Int
    let dropWeight: Double
    let isEnabled: Bool
}

struct FishCount: Identifiable, Equatable {
    var id: FishID { seaCritterID }

    let seaCritterID: FishID
    let displayName: String
    let rarity: FishRarity
    let sellValue: Int
    let assetName: String
    let sortOrder: Int
    let count: Int
}

struct FishSaleResult: Equatable {
    let balance: UserBerryBalance
    let soldFishCount: Int
    let soldBerryAmount: Int
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
            path: "/rest/v1/user_fish_catches?select=id,user_id,session_id,catch_index,sea_critter_id,rarity,sell_value,caught_at,sold_at,sold_for_berries&session_id=eq.\(sessionID.uuidString)&order=catch_index.asc,caught_at.asc",
            accessToken: authSession.accessToken
        )
    }

    func fetchInventory(for authSession: AuthSession) async throws -> [FishCatch] {
        try await fetchFishCatches(
            path: "/rest/v1/user_fish_catches?select=id,user_id,session_id,catch_index,sea_critter_id,rarity,sell_value,caught_at,sold_at,sold_for_berries&sold_at=is.null&order=caught_at.desc",
            accessToken: authSession.accessToken
        )
    }

    func fetchFishCatalog(for authSession: AuthSession) async throws -> [FishCatalogItem] {
        let response: [FishCatalogResponse] = try await send(
            path: "/rest/v1/sea_critters?select=id,display_name,rarity,sell_value,asset_name,sort_order,drop_weight,is_enabled&is_enabled=eq.true&order=sort_order.asc",
            method: "GET",
            accessToken: authSession.accessToken
        )

        return response.map(\.catalogItem)
    }

    func fetchCollectionCounts(for authSession: AuthSession) async throws -> [FishCount] {
        let response: [FishCountResponse] = try await send(
            path: "/rest/v1/user_fish_collection_counts?select=sea_critter_id,display_name,rarity,sell_value,asset_name,sort_order,count&order=sort_order.asc",
            method: "GET",
            accessToken: authSession.accessToken
        )

        return response.map(\.fishCount)
    }

    func fetchInventoryCounts(for authSession: AuthSession) async throws -> [FishCount] {
        let response: [FishCountResponse] = try await send(
            path: "/rest/v1/user_fish_inventory_counts?select=sea_critter_id,display_name,rarity,sell_value,asset_name,sort_order,count&order=sort_order.asc",
            method: "GET",
            accessToken: authSession.accessToken
        )

        return response.map(\.fishCount)
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
    let seaCritterId: FishID
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
            seaCritterID: seaCritterId,
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

private struct FishCatalogResponse: Decodable {
    let id: FishID
    let displayName: String
    let rarity: FishRarity
    let sellValue: Int
    let assetName: String
    let sortOrder: Int
    let dropWeight: Double
    let isEnabled: Bool

    var catalogItem: FishCatalogItem {
        FishCatalogItem(
            id: id,
            displayName: displayName,
            rarity: rarity,
            sellValue: sellValue,
            assetName: assetName,
            sortOrder: sortOrder,
            dropWeight: dropWeight,
            isEnabled: isEnabled
        )
    }
}

private struct FishCountResponse: Decodable {
    let seaCritterId: FishID
    let displayName: String
    let rarity: FishRarity
    let sellValue: Int
    let assetName: String
    let sortOrder: Int
    let count: Int

    var fishCount: FishCount {
        FishCount(
            seaCritterID: seaCritterId,
            displayName: displayName,
            rarity: rarity,
            sellValue: sellValue,
            assetName: assetName,
            sortOrder: sortOrder,
            count: count
        )
    }
}

private struct FishSaleResponse: Decodable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: String?
    let soldFishCount: Int
    let soldBerryAmount: Int

    var saleResult: FishSaleResult {
        FishSaleResult(
            balance: UserBerryBalance(
                berries: berries,
                completionStreak: completionStreak,
                lastCompletedOn: lastCompletedOn,
                lastCompletedAt: lastCompletedAt.flatMap(FocusDateFormatter.date(from:))
            ),
            soldFishCount: soldFishCount,
            soldBerryAmount: soldBerryAmount
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
