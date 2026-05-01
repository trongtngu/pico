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
    @Published private(set) var isLoadingBalance = false
    @Published private(set) var pendingBerryRewards: [PendingBerryReward] = []
    @Published private(set) var isLoadingPendingBerryRewards = false
    @Published private(set) var isCollectingBerries = false
    @Published private(set) var purchasingHat: AvatarHat?
    @Published var notice: String?

    var completionStreak: Int {
        balance.completionStreak
    }

    var pendingBerryTotal: Int {
        pendingBerryRewards.reduce(0) { $0 + $1.berryAmount }
    }

    var pendingRewardSummary: BerryRewardSummary {
        BerryRewardSummary.pending(pendingBerryRewards)
    }

    var hasPendingBerryRewards: Bool {
        pendingBerryTotal > 0
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

    func loadPendingBerryRewards(for session: AuthSession?, retryIfEmpty: Bool = false) async {
        guard let session, !isLoadingPendingBerryRewards else { return }

        isLoadingPendingBerryRewards = true
        notice = nil
        defer { isLoadingPendingBerryRewards = false }

        let maxAttempts = retryIfEmpty ? 4 : 1
        do {
            for attempt in 1...maxAttempts {
                pendingBerryRewards = try await berryService.fetchPendingBerryRewards(for: session)
                guard retryIfEmpty, pendingBerryRewards.isEmpty, attempt < maxAttempts else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func collectPendingBerryRewards(for session: AuthSession?) async -> BerryCollectionResult? {
        guard let session, !isCollectingBerries else { return nil }

        isCollectingBerries = true
        notice = nil
        defer { isCollectingBerries = false }

        do {
            let result = try await berryService.collectPendingBerryRewards(for: session)
            balance = result.balance
            pendingBerryRewards.removeAll()
            return result
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
    }

    func purchaseAvatarHat(_ hat: AvatarHat, for session: AuthSession?) async -> HatPurchaseResult? {
        guard let session, purchasingHat == nil else { return nil }

        purchasingHat = hat
        notice = nil
        defer { purchasingHat = nil }

        do {
            let result = try await berryService.purchaseAvatarHat(hat, for: session)
            balance = result.balance
            return result
        } catch {
            notice = displayMessage(for: error)
            return nil
        }
    }

    func clear() {
        balance = .zero
        pendingBerryRewards = []
        notice = nil
        isLoadingBalance = false
        isLoadingPendingBerryRewards = false
        isCollectingBerries = false
        purchasingHat = nil
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
