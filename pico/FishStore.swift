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
    @Published private(set) var fishCatalogIslandID: String = PicoIsland.original.backendID
    @Published private(set) var fishCatalogsByIslandID: [String: [FishCatalogItem]] = [:]
    @Published private(set) var collectionCounts: [FishCount] = []
    @Published private(set) var collectionCountsIslandID: String = PicoIsland.original.backendID
    @Published private(set) var islandCollectionCounts: [String: [FishCount]] = [:]
    @Published private(set) var inventoryCounts: [FishCount] = []
    @Published private(set) var isLoadingSessionCatches = false
    @Published private(set) var isLoadingInventory = false
    @Published private(set) var isLoadingFishCatalog = false
    @Published private(set) var loadingFishCatalogIslandIDs: Set<String> = []
    @Published private(set) var isLoadingCollectionCounts = false
    @Published private(set) var isLoadingIslandCollectionCounts = false
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

    func fishCatalog(for islandID: String) -> [FishCatalogItem] {
        let resolvedIslandID = islandID.isEmpty ? PicoIsland.original.backendID : islandID

        if let cachedCatalog = fishCatalogsByIslandID[resolvedIslandID] {
            return cachedCatalog
        }

        if fishCatalogIslandID == resolvedIslandID {
            return fishCatalog
        }

        return []
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

    func loadFishCatalog(
        for session: AuthSession?,
        islandID: String = PicoIsland.original.backendID,
        forceReload: Bool = false
    ) async {
        guard let session, !isLoadingFishCatalog else { return }

        let resolvedIslandID = islandID.isEmpty ? PicoIsland.original.backendID : islandID
        guard forceReload || fishCatalog.isEmpty || fishCatalogIslandID != resolvedIslandID else { return }

        if fishCatalogIslandID != resolvedIslandID {
            fishCatalog = []
        }
        fishCatalogIslandID = resolvedIslandID
        isLoadingFishCatalog = true
        notice = nil
        defer { isLoadingFishCatalog = false }

        do {
            let nextCatalog = try await fishService.fetchFishCatalog(for: session, islandID: resolvedIslandID)
            fishCatalog = nextCatalog
            fishCatalogsByIslandID[resolvedIslandID] = nextCatalog
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadPreviewFishCatalog(
        for session: AuthSession?,
        islandID: String,
        forceReload: Bool = false
    ) async {
        guard let session else { return }

        let resolvedIslandID = islandID.isEmpty ? PicoIsland.original.backendID : islandID
        guard forceReload || fishCatalogsByIslandID[resolvedIslandID] == nil else { return }
        guard !loadingFishCatalogIslandIDs.contains(resolvedIslandID) else { return }

        loadingFishCatalogIslandIDs.insert(resolvedIslandID)
        notice = nil
        defer { loadingFishCatalogIslandIDs.remove(resolvedIslandID) }

        do {
            let nextCatalog = try await fishService.fetchFishCatalog(for: session, islandID: resolvedIslandID)
            fishCatalogsByIslandID[resolvedIslandID] = nextCatalog
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadCollectionCounts(
        for session: AuthSession?,
        islandID: String = PicoIsland.original.backendID,
        forceReload: Bool = false
    ) async {
        guard let session, !isLoadingCollectionCounts else { return }

        let resolvedIslandID = islandID.isEmpty ? PicoIsland.original.backendID : islandID
        guard forceReload || collectionCounts.isEmpty || collectionCountsIslandID != resolvedIslandID else { return }

        if collectionCountsIslandID != resolvedIslandID {
            collectionCounts = []
        }
        collectionCountsIslandID = resolvedIslandID
        isLoadingCollectionCounts = true
        notice = nil
        defer { isLoadingCollectionCounts = false }

        do {
            let counts = try await fishService.fetchCollectionCounts(for: session, islandID: resolvedIslandID)
            collectionCounts = counts
            islandCollectionCounts[resolvedIslandID] = counts
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func loadIslandCollectionCounts(
        for session: AuthSession?,
        islandIDs: [String],
        forceReload: Bool = false
    ) async {
        guard let session, !isLoadingIslandCollectionCounts else { return }

        let resolvedIslandIDs = islandIDs
            .map { $0.isEmpty ? PicoIsland.original.backendID : $0 }
            .uniqued()

        guard forceReload || resolvedIslandIDs.contains(where: { islandCollectionCounts[$0] == nil }) else { return }

        isLoadingIslandCollectionCounts = true
        notice = nil
        defer { isLoadingIslandCollectionCounts = false }

        do {
            for islandID in resolvedIslandIDs where forceReload || islandCollectionCounts[islandID] == nil {
                let counts = try await fishService.fetchCollectionCounts(for: session, islandID: islandID)
                islandCollectionCounts[islandID] = counts

                if collectionCountsIslandID == islandID {
                    collectionCounts = counts
                }
            }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func prepareIslandFishData(islandID: String) {
        let resolvedIslandID = islandID.isEmpty ? PicoIsland.original.backendID : islandID
        guard fishCatalogIslandID != resolvedIslandID || collectionCountsIslandID != resolvedIslandID else { return }

        fishCatalog = []
        collectionCounts = []
        fishCatalogIslandID = resolvedIslandID
        collectionCountsIslandID = resolvedIslandID

        if let cachedCatalog = fishCatalogsByIslandID[resolvedIslandID] {
            fishCatalog = cachedCatalog
        }

        if let counts = islandCollectionCounts[resolvedIslandID] {
            collectionCounts = counts
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
        fishCatalogIslandID = PicoIsland.original.backendID
        fishCatalogsByIslandID = [:]
        collectionCounts = []
        collectionCountsIslandID = PicoIsland.original.backendID
        islandCollectionCounts = [:]
        inventoryCounts = []
        isLoadingInventory = false
        isLoadingFishCatalog = false
        loadingFishCatalogIslandIDs = []
        isLoadingCollectionCounts = false
        isLoadingIslandCollectionCounts = false
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

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
