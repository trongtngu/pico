//
//  PicoPlusStore.swift
//  pico
//
//  Created by Codex on 15/5/2026.
//

import Combine
import Foundation

@MainActor
final class PicoPlusStore: ObservableObject {
    @Published private(set) var entitlement: PicoPlusEntitlement = .free
    @Published private(set) var capabilities: PicoPlusCapabilities = .free
    @Published private(set) var isLoading = false
    @Published var notice: String?

    private let service: PicoPlusService

    init(service: PicoPlusService? = nil) {
        self.service = service ?? PicoPlusService()
    }

    var isPlusActive: Bool {
        capabilities.isPlusActive
    }

    func configureIdentity(session: AuthSession?, profile: UserProfile?) {
        service.identifyUser(session: session, profile: profile)
    }

    func refresh(for authSession: AuthSession?) async {
        guard let authSession else {
            apply(.free)
            return
        }

        isLoading = true
        notice = nil
        defer { isLoading = false }

        do {
            let entitlement = try await service.fetchEntitlement(for: authSession)
            apply(entitlement)
            AnalyticsService.track(.picoPlusEntitlementRefreshSucceeded(isActive: entitlement.isActive))
        } catch {
            apply(.free)
            AnalyticsService.track(.picoPlusEntitlementRefreshFailed(message: displayMessage(for: error)))
        }
    }

    func presentPaywall(source: PicoPlusPaywallSource, authSession: AuthSession?) async {
        notice = nil
        let placement = source.placement
        trackGateHit(for: source)
        AnalyticsService.track(.picoPlusPaywallTriggered(placement: placement, source: source))

        do {
            let outcome = try await service.presentPaywall(placement: placement)
            AnalyticsService.track(.picoPlusPaywallFinished(
                placement: placement,
                source: source,
                outcome: outcome.analyticsValue
            ))
            await refresh(for: authSession)
        } catch {
            notice = displayMessage(for: error)
            AnalyticsService.track(.picoPlusPaywallFailed(
                placement: placement,
                source: source,
                message: displayMessage(for: error)
            ))
        }
    }

    private func trackGateHit(for source: PicoPlusPaywallSource) {
        switch source {
        case .onboardingComplete:
            AnalyticsService.track(.picoPlusOnboardingGateHit())
        case .calendarView:
            AnalyticsService.track(.picoPlusCalendarGateHit())
        case .bondReward(let residentID, let bondLevel, _):
            AnalyticsService.track(.picoPlusBondRewardGateHit(
                residentID: residentID,
                bondLevel: bondLevel
            ))
        case .largeGroupSession(let currentMembers, let selectedInvites, let limit, _):
            AnalyticsService.track(.picoPlusGroupGateHit(
                currentMembers: currentMembers,
                selectedInvites: selectedInvites,
                limit: limit
            ))
        case .plusCosmetic(let itemID, let itemType, let itemKey, _):
            AnalyticsService.track(.picoPlusCosmeticGateHit(
                itemID: itemID,
                itemType: itemType,
                itemKey: itemKey
            ))
        }
    }

    private func apply(_ entitlement: PicoPlusEntitlement) {
        self.entitlement = entitlement
        capabilities = PicoPlusEntitlements.capabilities(isPlusActive: entitlement.isActive)
    }

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

private extension PicoPlusPaywallOutcome {
    var analyticsValue: String {
        switch self {
        case .purchased:
            "purchased"
        case .restored:
            "restored"
        case .declined:
            "declined"
        case .skipped(let reason):
            "skipped_\(reason)"
        }
    }
}
