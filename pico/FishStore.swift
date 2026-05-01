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
    @Published private(set) var fishCatalog: [FishCatalogItem] = []
    @Published private(set) var collectionCounts: [FishCount] = []
    @Published private(set) var inventoryCounts: [FishCount] = []
    @Published private(set) var isLoadingSessionCatches = false
    @Published private(set) var isLoadingInventory = false
    @Published private(set) var isLoadingFishCatalog = false
    @Published private(set) var isLoadingCollectionCounts = false
    @Published private(set) var isLoadingInventoryCounts = false
    @Published private(set) var isSellingFish = false
    @Published var notice: String?

    var currentSessionCatches: [FishCatch] {
        guard let currentSessionID else { return [] }
        return sessionCatches[currentSessionID] ?? []
    }

    var inventorySummary: FishCatchSummary {
        FishCatchSummary.catches(inventory)
    }

    var collectionCountByFishID: [FishID: FishCount] {
        Dictionary(uniqueKeysWithValues: collectionCounts.map { ($0.seaCritterID, $0) })
    }

    var inventoryCountByFishID: [FishID: FishCount] {
        Dictionary(uniqueKeysWithValues: inventoryCounts.map { ($0.seaCritterID, $0) })
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

    func loadFishCatalog(for session: AuthSession?) async {
        guard let session, !isLoadingFishCatalog else { return }

        isLoadingFishCatalog = true
        notice = nil
        defer { isLoadingFishCatalog = false }

        do {
            fishCatalog = try await fishService.fetchFishCatalog(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadCollectionCounts(for session: AuthSession?) async {
        guard let session, !isLoadingCollectionCounts else { return }

        isLoadingCollectionCounts = true
        notice = nil
        defer { isLoadingCollectionCounts = false }

        do {
            collectionCounts = try await fishService.fetchCollectionCounts(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadInventoryCounts(for session: AuthSession?) async {
        guard let session, !isLoadingInventoryCounts else { return }

        isLoadingInventoryCounts = true
        notice = nil
        defer { isLoadingInventoryCounts = false }

        do {
            inventoryCounts = try await fishService.fetchInventoryCounts(for: session)
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
            let soldCatches = inventory.filter { soldIDs.contains($0.id) }

            inventory.removeAll { soldIDs.contains($0.id) }
            sessionCatches = sessionCatches.mapValues { catches in
                catches.map { soldIDs.contains($0.id) ? $0.sold(at: soldAt) : $0 }
            }
            decrementInventoryCounts(for: soldCatches)

            notice = "Sold \(result.soldFishCount) fish for \(formattedBerryCount(result.soldBerryAmount))."
            return result
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
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
        fishCatalog = []
        collectionCounts = []
        inventoryCounts = []
        isLoadingInventory = false
        isLoadingFishCatalog = false
        isLoadingCollectionCounts = false
        isLoadingInventoryCounts = false
    }

    private func decrementInventoryCounts(for soldCatches: [FishCatch]) {
        guard !soldCatches.isEmpty, !inventoryCounts.isEmpty else { return }

        let soldCounts = Dictionary(grouping: soldCatches, by: \.seaCritterID)
            .mapValues(\.count)

        inventoryCounts = inventoryCounts.compactMap { countRow in
            let remainingCount = countRow.count - soldCounts[countRow.seaCritterID, default: 0]
            guard remainingCount > 0 else { return nil }

            return FishCount(
                seaCritterID: countRow.seaCritterID,
                displayName: countRow.displayName,
                rarity: countRow.rarity,
                sellValue: countRow.sellValue,
                assetName: countRow.assetName,
                sortOrder: countRow.sortOrder,
                count: remainingCount
            )
        }
    }

    private func displayMessage(for error: Error) -> String? {
        guard !error.isCancellation else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
