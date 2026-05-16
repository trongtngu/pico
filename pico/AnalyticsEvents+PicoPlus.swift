//
//  AnalyticsEvents+PicoPlus.swift
//  pico
//
//  Created by Codex on 15/5/2026.
//

import Foundation

extension AnalyticsEvent {
    static func picoPlusEntitlementRefreshSucceeded(isActive: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_refresh_ok",
            parameters: ["is_active": isActive]
        )
    }

    static func picoPlusEntitlementRefreshFailed(message: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_refresh_failed",
            parameters: ["message": message]
        )
    }

    static func picoPlusPaywallTriggered(placement: PicoPlusPlacement, source: PicoPlusPaywallSource) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_paywall_trigger",
            parameters: [
                "placement": placement.rawValue,
                "source": source.analyticsValue
            ]
        )
    }

    static func picoPlusPaywallFinished(
        placement: PicoPlusPlacement,
        source: PicoPlusPaywallSource,
        outcome: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_paywall_finish",
            parameters: [
                "placement": placement.rawValue,
                "source": source.analyticsValue,
                "outcome": outcome
            ]
        )
    }

    static func picoPlusPaywallFailed(
        placement: PicoPlusPlacement,
        source: PicoPlusPaywallSource,
        message: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_paywall_failed",
            parameters: [
                "placement": placement.rawValue,
                "source": source.analyticsValue,
                "message": message
            ]
        )
    }

    static func picoPlusGroupGateHit(currentMembers: Int, selectedInvites: Int, limit: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_group_gate_hit",
            parameters: [
                "current_members": currentMembers,
                "selected_invites": selectedInvites,
                "limit": limit
            ]
        )
    }

    static func picoPlusCalendarGateHit() -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_calendar_gate_hit",
            parameters: [:]
        )
    }

    static func picoPlusBondRewardGateHit(residentID: String, bondLevel: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_bond_gate_hit",
            parameters: [
                "resident_id": residentID,
                "bond_level": bondLevel
            ]
        )
    }

    static func picoPlusCosmeticGateHit(itemID: String, itemType: String, itemKey: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "pico_plus_cosmetic_gate_hit",
            parameters: [
                "item_id": itemID,
                "item_type": itemType,
                "item_key": itemKey
            ]
        )
    }

}
