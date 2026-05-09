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

enum StoreItemType: String, Codable, Equatable, Hashable, CaseIterable {
    case hat
    case island
}

struct StoreItem: Identifiable, Equatable, Hashable {
    let id: String
    let itemType: StoreItemType
    let itemKey: String
    let displayName: String
    let berryPrice: Int
    let isEnabled: Bool
    let isLimited: Bool
    let isPaidOnly: Bool
    let sortOrder: Int

    var avatarHat: AvatarHat? {
        guard itemType == .hat, let rawValue = Int(itemKey) else { return nil }
        return AvatarHat(rawValue: rawValue)
    }

    var picoIsland: PicoIsland? {
        guard itemType == .island else { return nil }
        return PicoIsland(backendID: itemKey)
    }
}

struct StoreInventoryItem: Equatable, Hashable {
    let storeItemID: String
    let itemType: StoreItemType
    let itemKey: String
    let displayName: String
    let berryPrice: Int
    let acquiredAt: Date?
    let acquisitionSource: String
}

struct StorePurchaseResult: Equatable {
    let balance: UserBerryBalance
    let ownedStoreItemIDs: Set<String>
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

    func fetchStoreCatalog(for authSession: AuthSession) async throws -> [StoreItem] {
        let response: [StoreItemResponse] = try await send(
            path: "/rest/v1/rpc/fetch_store_catalog",
            method: "POST",
            body: EmptyBerryRequest(),
            accessToken: authSession.accessToken
        )

        return response.map(\.storeItem)
            .sorted {
                if $0.itemType != $1.itemType {
                    return $0.itemType.sortRank < $1.itemType.sortRank
                }

                return $0.sortOrder < $1.sortOrder
            }
    }

    func fetchUserStoreInventory(for authSession: AuthSession) async throws -> [StoreInventoryItem] {
        let response: [StoreInventoryResponse] = try await send(
            path: "/rest/v1/rpc/fetch_user_store_inventory",
            method: "POST",
            body: EmptyBerryRequest(),
            accessToken: authSession.accessToken
        )

        return response.map(\.inventoryItem)
    }

    func purchaseStoreItem(_ item: StoreItem, for authSession: AuthSession) async throws -> StorePurchaseResult {
        try await purchaseStoreItem(type: item.itemType, key: item.itemKey, for: authSession)
    }

    func purchaseStoreItem(
        type: StoreItemType,
        key: String,
        for authSession: AuthSession
    ) async throws -> StorePurchaseResult {
        let response: [StorePurchaseResponse] = try await send(
            path: "/rest/v1/rpc/purchase_store_item",
            method: "POST",
            body: StorePurchaseRequest(itemType: type.rawValue, itemKey: key),
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

private struct StoreItemResponse: Decodable {
    let id: String
    let itemType: StoreItemType
    let itemKey: String
    let displayName: String
    let berryPrice: Int
    let isEnabled: Bool
    let isLimited: Bool
    let isPaidOnly: Bool
    let sortOrder: Int

    var storeItem: StoreItem {
        StoreItem(
            id: id,
            itemType: itemType,
            itemKey: itemKey,
            displayName: displayName,
            berryPrice: berryPrice,
            isEnabled: isEnabled,
            isLimited: isLimited,
            isPaidOnly: isPaidOnly,
            sortOrder: sortOrder
        )
    }
}

private struct StoreInventoryResponse: Decodable {
    let storeItemId: String
    let itemType: StoreItemType
    let itemKey: String
    let displayName: String
    let berryPrice: Int
    let acquiredAt: String?
    let acquisitionSource: String

    var inventoryItem: StoreInventoryItem {
        StoreInventoryItem(
            storeItemID: storeItemId,
            itemType: itemType,
            itemKey: itemKey,
            displayName: displayName,
            berryPrice: berryPrice,
            acquiredAt: acquiredAt.flatMap(FocusDateFormatter.date(from:)),
            acquisitionSource: acquisitionSource
        )
    }
}

private struct StorePurchaseRequest: Encodable {
    let itemType: String
    let itemKey: String
}

private struct StorePurchaseResponse: Decodable {
    let berries: Int
    let completionStreak: Int
    let lastCompletedOn: String?
    let lastCompletedAt: String?
    let ownedStoreItemIds: [String]

    var purchaseResult: StorePurchaseResult {
        StorePurchaseResult(
            balance: UserBerryBalance(
                berries: berries,
                completionStreak: completionStreak,
                lastCompletedOn: lastCompletedOn,
                lastCompletedAt: lastCompletedAt.flatMap(FocusDateFormatter.date(from:))
            ),
            ownedStoreItemIDs: Set(ownedStoreItemIds)
        )
    }
}

private extension StoreItemType {
    var sortRank: Int {
        switch self {
        case .island:
            0
        case .hat:
            1
        }
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
