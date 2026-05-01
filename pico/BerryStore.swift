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
    @Published private(set) var purchasingHat: AvatarHat?
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
        notice = nil
        isLoadingBalance = false
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
