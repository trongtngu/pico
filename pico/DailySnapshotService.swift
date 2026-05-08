//
//  DailySnapshotService.swift
//  pico
//
//  Created by Codex on 7/5/2026.
//

import Foundation

enum DailySnapshotLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct DailySnapshotDay: RawRepresentable, Codable, Hashable, Comparable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(date: Date = Date(), calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func date(calendar: Calendar = .current) -> Date? {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func < (lhs: DailySnapshotDay, rhs: DailySnapshotDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct DailyVillageSnapshotVisitor: Identifiable, Equatable {
    var id: UUID { profile.userID }

    let profile: UserProfile
    let bondLevel: Int
    let completedPairSessions: Int
}

struct DailyVillageSnapshot: Identifiable, Equatable {
    var id: String { "\(ownerID.uuidString)-\(snapshotDay.rawValue)" }

    let ownerID: UUID
    let snapshotDay: DailySnapshotDay
    let userTimezone: String
    let islandID: String
    let ownerProfile: UserProfile
    let visitors: [DailyVillageSnapshotVisitor]
    let focusSessionIDs: [UUID]
    let totalFocusSeconds: Int
    let fishCaughtCount: Int
    let fishCounts: [FishCount]
    let createdAt: Date?
    let updatedAt: Date?
    let notice: String?
}

enum DailySnapshotServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse(String? = nil)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Add your Supabase project URL and anon key in SupabaseConfig.swift."
        case .invalidResponse(let message):
            message ?? "Supabase returned daily snapshot data the app could not read."
        case .requestFailed(let message):
            message
        }
    }
}

final class DailySnapshotService {
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

    func fetchSnapshot(
        day: DailySnapshotDay,
        for authSession: AuthSession
    ) async throws -> DailyVillageSnapshot? {
        let response: [DailyVillageSnapshotResponse] = try await send(
            path: "/rest/v1/rpc/fetch_daily_village_snapshot",
            method: "POST",
            body: FetchDailySnapshotRequest(requestedSnapshotDay: day),
            accessToken: authSession.accessToken
        )

        return response.first?.dailyVillageSnapshot
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
            throw DailySnapshotServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw DailySnapshotServiceError.missingConfiguration
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
            throw DailySnapshotServiceError.invalidResponse()
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(DailySnapshotSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw DailySnapshotServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw DailySnapshotServiceError.invalidResponse()
        }
    }
}

private struct FetchDailySnapshotRequest: Encodable {
    let requestedSnapshotDay: DailySnapshotDay
}

private struct DailyVillageSnapshotResponse: Decodable {
    let ownerId: UUID
    let snapshotDay: DailySnapshotDay
    let userTimezone: String
    let islandId: String
    let ownerProfile: DailySnapshotProfileResponse
    let visitors: [DailySnapshotVisitorResponse]
    let skippedVisitorCount: Int
    let focusSessionIds: [UUID]
    let totalFocusSeconds: Int
    let fishCaughtCount: Int
    let fishCounts: [DailySnapshotFishCountResponse]
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case ownerId
        case snapshotDay
        case userTimezone
        case islandId
        case ownerProfile
        case visitors
        case focusSessionIds
        case totalFocusSeconds
        case fishCaughtCount
        case fishCounts
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        snapshotDay = try container.decode(DailySnapshotDay.self, forKey: .snapshotDay)
        userTimezone = try container.decode(String.self, forKey: .userTimezone)
        islandId = try container.decode(String.self, forKey: .islandId)
        ownerProfile = try container.decode(DailySnapshotProfileResponse.self, forKey: .ownerProfile)
        focusSessionIds = try container.decodeIfPresent([UUID].self, forKey: .focusSessionIds) ?? []
        totalFocusSeconds = try container.decodeIfPresent(Int.self, forKey: .totalFocusSeconds) ?? 0
        fishCaughtCount = try container.decodeIfPresent(Int.self, forKey: .fishCaughtCount) ?? 0
        fishCounts = try container.decodeIfPresent([DailySnapshotFishCountResponse].self, forKey: .fishCounts) ?? []
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)

        let visitorList = Self.decodeVisitors(from: container)
        visitors = visitorList.values
        skippedVisitorCount = visitorList.skippedCount
    }

    var dailyVillageSnapshot: DailyVillageSnapshot {
        DailyVillageSnapshot(
            ownerID: ownerId,
            snapshotDay: snapshotDay,
            userTimezone: userTimezone,
            islandID: islandId,
            ownerProfile: ownerProfile.userProfile,
            visitors: visitors.map(\.dailyVillageSnapshotVisitor),
            focusSessionIDs: focusSessionIds,
            totalFocusSeconds: totalFocusSeconds,
            fishCaughtCount: fishCaughtCount,
            fishCounts: fishCounts.map(\.fishCount),
            createdAt: FocusDateFormatter.date(from: createdAt),
            updatedAt: FocusDateFormatter.date(from: updatedAt),
            notice: skippedVisitorCount > 0 ? skippedVisitorNotice : nil
        )
    }

    private var skippedVisitorNotice: String {
        skippedVisitorCount == 1
            ? "One snapshot visitor could not be loaded."
            : "\(skippedVisitorCount) snapshot visitors could not be loaded."
    }

    private static func decodeVisitors(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> (values: [DailySnapshotVisitorResponse], skippedCount: Int) {
        guard container.contains(.visitors) else {
            return ([], 0)
        }

        do {
            guard let visitors = try container.decodeIfPresent(
                [LossyDailySnapshotVisitorResponse].self,
                forKey: .visitors
            ) else {
                return ([], 0)
            }

            let values = visitors.compactMap(\.value)
            return (values, visitors.count - values.count)
        } catch {
            return ([], 1)
        }
    }
}

private struct LossyDailySnapshotVisitorResponse: Decodable {
    let value: DailySnapshotVisitorResponse?

    init(from decoder: Decoder) throws {
        value = try? DailySnapshotVisitorResponse(from: decoder)
    }
}

private struct DailySnapshotProfileResponse: Decodable {
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

private struct DailySnapshotVisitorResponse: Decodable {
    let userId: UUID
    let username: String
    let displayName: String
    let avatarConfig: AvatarConfig
    let bondLevel: Int
    let completedPairSessions: Int

    var dailyVillageSnapshotVisitor: DailyVillageSnapshotVisitor {
        DailyVillageSnapshotVisitor(
            profile: UserProfile(
                userID: userId,
                username: username,
                displayName: displayName,
                avatarConfig: avatarConfig
            ),
            bondLevel: bondLevel,
            completedPairSessions: completedPairSessions
        )
    }
}

private struct DailySnapshotFishCountResponse: Decodable {
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

private struct DailySnapshotSupabaseErrorResponse: Decodable {
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
