//
//  BerryStore.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import Foundation
import Combine

@MainActor
final class BerryStore: ObservableObject {
    @Published private(set) var balance: UserBerryBalance = .zero
    @Published private(set) var storeCatalog: [StoreItem] = []
    @Published private(set) var ownedStoreItemIDs: Set<String> = []
    @Published private(set) var isLoadingBalance = false
    @Published private(set) var isLoadingStoreCatalog = false
    @Published private(set) var isLoadingStoreInventory = false
    @Published private(set) var purchasingStoreItemID: String?
    @Published var notice: String?

    var completionStreak: Int {
        balance.completionStreak
    }

    private let berryService: BerryService

    init(berryService: BerryService? = nil) {
        self.berryService = berryService ?? BerryService()
    }

    func loadBalance(for session: AuthSession?) async {
        guard let session, !isLoadingBalance else { return }

        isLoadingBalance = true
        notice = nil
        defer { isLoadingBalance = false }

        do {
            balance = try await berryService.fetchUserBerryBalance(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func applyBalance(_ balance: UserBerryBalance) {
        self.balance = balance
        notice = nil
    }

    func loadStoreCatalog(for session: AuthSession?) async {
        guard let session, !isLoadingStoreCatalog else { return }

        isLoadingStoreCatalog = true
        notice = nil
        defer { isLoadingStoreCatalog = false }

        do {
            storeCatalog = try await berryService.fetchStoreCatalog(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    @discardableResult
    func loadStoreInventory(for session: AuthSession?) async -> Set<String>? {
        guard let session, !isLoadingStoreInventory else { return nil }

        isLoadingStoreInventory = true
        notice = nil
        defer { isLoadingStoreInventory = false }

        do {
            let inventory = try await berryService.fetchUserStoreInventory(for: session)
            ownedStoreItemIDs = Set(inventory.map(\.storeItemID))
            return ownedStoreItemIDs
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
    }

    func applyOwnedStoreItemIDs(_ itemIDs: Set<String>) {
        ownedStoreItemIDs = itemIDs
        notice = nil
    }

    func purchaseStoreItem(_ item: StoreItem, for session: AuthSession?) async -> StorePurchaseResult? {
        guard let session, purchasingStoreItemID == nil else { return nil }

        purchasingStoreItemID = item.id
        notice = nil
        defer { purchasingStoreItemID = nil }

        do {
            let result = try await berryService.purchaseStoreItem(item, for: session)
            balance = result.balance
            ownedStoreItemIDs = result.ownedStoreItemIDs
            return result
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
    }

    func clear() {
        balance = .zero
        storeCatalog = []
        ownedStoreItemIDs = []
        notice = nil
        isLoadingBalance = false
        isLoadingStoreCatalog = false
        isLoadingStoreInventory = false
        purchasingStoreItemID = nil
    }

    #if DEBUG
    static var preview: BerryStore {
        let store = BerryStore()
        store.balance = UserBerryBalance(
            berries: 12,
            completionStreak: 4,
            lastCompletedOn: nil,
            lastCompletedAt: nil
        )
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String? {
        guard !error.isCancellation else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
