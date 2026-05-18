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
            Analytics.track(AnalyticsEvent(
                id: .picoPlusRefreshSucceeded,
                parameters: [.isActive: .bool(entitlement.isActive)]
            ))
        } catch {
            apply(.free)
            Analytics.track(AnalyticsEvent(
                id: .picoPlusRefreshFailed,
                parameters: [.message: .string(analyticsErrorCategory(for: error))]
            ))
        }
    }

    func presentPaywall(source: PicoPlusPaywallSource, authSession: AuthSession?) async {
        guard let authSession else {
            notice = "Create an account or log in to unlock Plus."
            Analytics.track(AnalyticsEvent(
                id: .picoPlusPaywallFailed,
                parameters: [
                    .placement: .string(source.placement.rawValue),
                    .source: .string(source.analyticsValue),
                    .message: .string("missing_auth_session")
                ]
            ))
            return
        }

        notice = nil
        let placement = source.placement
        trackGateHit(for: source)
        Analytics.track(AnalyticsEvent(
            id: .picoPlusPaywallTriggered,
            parameters: [
                .placement: .string(placement.rawValue),
                .source: .string(source.analyticsValue)
            ]
        ))

        do {
            let outcome = try await service.presentPaywall(placement: placement)
            Analytics.track(AnalyticsEvent(
                id: .picoPlusPaywallFinished,
                parameters: [
                    .placement: .string(placement.rawValue),
                    .source: .string(source.analyticsValue),
                    .outcome: .string(outcome.analyticsValue)
                ]
            ))
            await refresh(for: authSession)
        } catch {
            notice = displayMessage(for: error)
            Analytics.track(AnalyticsEvent(
                id: .picoPlusPaywallFailed,
                parameters: [
                    .placement: .string(placement.rawValue),
                    .source: .string(source.analyticsValue),
                    .message: .string(analyticsErrorCategory(for: error))
                ]
            ))
        }
    }

    private func trackGateHit(for source: PicoPlusPaywallSource) {
        switch source {
        case .onboardingComplete:
            Analytics.track(AnalyticsEvent(id: .picoPlusOnboardingGateHit))
        case .calendarView:
            Analytics.track(AnalyticsEvent(id: .picoPlusCalendarGateHit))
        case .bondReward(let residentID, let bondLevel, _):
            Analytics.track(AnalyticsEvent(
                id: .picoPlusBondRewardGateHit,
                parameters: [
                    .residentID: .string(residentID),
                    .bondLevel: .int(bondLevel)
                ]
            ))
        case .largeGroupSession(let currentMembers, let selectedInvites, let limit, _):
            Analytics.track(AnalyticsEvent(
                id: .picoPlusGroupGateHit,
                parameters: [
                    .currentMembers: .int(currentMembers),
                    .selectedInvites: .int(selectedInvites),
                    .limit: .int(limit)
                ]
            ))
        case .plusCosmetic(let itemID, let itemType, let itemKey, _):
            Analytics.track(AnalyticsEvent(
                id: .picoPlusCosmeticGateHit,
                parameters: [
                    .itemID: .string(itemID),
                    .itemType: .string(itemType),
                    .itemKey: .string(itemKey)
                ]
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

    private func analyticsErrorCategory(for error: Error) -> String {
        if error.isCancellation {
            return "cancelled"
        }

        guard let serviceError = error as? PicoPlusServiceError else {
            return "unknown"
        }

        switch serviceError {
        case .missingConfiguration:
            return "missing_configuration"
        case .invalidResponse:
            return "invalid_response"
        case .paywallNotConfigured:
            return "paywall_not_configured"
        case .paywallSkipped:
            return "paywall_skipped"
        case .requestFailed:
            return "request_failed"
        }
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
