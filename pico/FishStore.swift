//
//  FishStore.swift
//  pico
//
//  Created by Codex on 1/5/2026.
//

import Foundation
import Combine

@MainActor
final class FishStore: ObservableObject {
    @Published private(set) var sessionCatches: [UUID: [FishCatch]] = [:]
    @Published private(set) var currentSessionID: UUID?
    @Published private(set) var inventory: [FishCatch] = []
    @Published private(set) var isLoadingSessionCatches = false
    @Published private(set) var isLoadingInventory = false
    @Published private(set) var isSellingFish = false
    @Published var notice: String?

    var currentSessionCatches: [FishCatch] {
        guard let currentSessionID else { return [] }
        return sessionCatches[currentSessionID] ?? []
    }

    var inventorySummary: FishCatchSummary {
        FishCatchSummary.catches(inventory)
    }

    private let fishService: FishService

    init(fishService: FishService? = nil) {
        self.fishService = fishService ?? FishService()
    }

    func loadSessionCatches(
        sessionID: UUID,
        for session: AuthSession?,
        retryIfEmpty: Bool = false
    ) async {
        guard let session, !isLoadingSessionCatches else { return }

        currentSessionID = sessionID
        if sessionCatches[sessionID] == nil {
            sessionCatches[sessionID] = []
        }

        isLoadingSessionCatches = true
        notice = nil
        defer { isLoadingSessionCatches = false }

        let maxAttempts = retryIfEmpty ? 4 : 1
        do {
            for attempt in 1...maxAttempts {
                let catches = try await fishService.fetchSessionCatches(sessionID: sessionID, for: session)
                sessionCatches[sessionID] = catches
                guard retryIfEmpty, catches.isEmpty, attempt < maxAttempts else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadInventory(for session: AuthSession?) async {
        guard let session, !isLoadingInventory else { return }

        isLoadingInventory = true
        notice = nil
        defer { isLoadingInventory = false }

        do {
            inventory = try await fishService.fetchInventory(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func sellFish(catchIDs: [UUID], for session: AuthSession?) async -> FishSaleResult? {
        guard let session, !isSellingFish, !catchIDs.isEmpty else { return nil }

        isSellingFish = true
        notice = nil
        defer { isSellingFish = false }

        do {
            let result = try await fishService.sellFish(catchIDs: catchIDs, for: session)
            let soldIDs = Set(catchIDs)
            let soldAt = Date()

            inventory.removeAll { soldIDs.contains($0.id) }
            sessionCatches = sessionCatches.mapValues { catches in
                catches.map { soldIDs.contains($0.id) ? $0.sold(at: soldAt) : $0 }
            }

            notice = "Sold \(result.soldFishCount) fish for \(formattedBerryCount(result.soldBerryAmount))."
            return result
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
    }

    func loadMockSessionCatches() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-00000000F150") ?? UUID()
        let userID = UUID(uuidString: "00000000-0000-0000-0000-00000000F151")
        let caughtAt = Date()

        currentSessionID = sessionID
        sessionCatches[sessionID] = [
            FishCatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000F1A1") ?? UUID(),
                userID: userID,
                sessionID: sessionID,
                catchIndex: 1,
                fishType: .bass,
                rarity: .common,
                sellValue: FishType.bass.sellValue,
                caughtAt: caughtAt,
                soldAt: nil,
                soldForBerries: nil
            ),
            FishCatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000F1A2") ?? UUID(),
                userID: userID,
                sessionID: sessionID,
                catchIndex: 2,
                fishType: .salmon,
                rarity: .uncommon,
                sellValue: FishType.salmon.sellValue,
                caughtAt: caughtAt,
                soldAt: nil,
                soldForBerries: nil
            ),
            FishCatch(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000F1A3") ?? UUID(),
                userID: userID,
                sessionID: sessionID,
                catchIndex: 3,
                fishType: .tuna,
                rarity: .rare,
                sellValue: FishType.tuna.sellValue,
                caughtAt: caughtAt,
                soldAt: nil,
                soldForBerries: nil
            )
        ]
        isLoadingSessionCatches = false
        notice = nil
    }

    func clearSessionCatches() {
        sessionCatches = [:]
        currentSessionID = nil
        isLoadingSessionCatches = false
        isSellingFish = false
        notice = nil
    }

    func clear() {
        clearSessionCatches()
        inventory = []
        isLoadingInventory = false
    }

    private func displayMessage(for error: Error) -> String? {
        guard !error.isCancellation else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
