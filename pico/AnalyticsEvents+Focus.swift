//
//  AnalyticsEvents+Focus.swift
//  pico
//
//  Created by Codex on 9/5/2026.
//

import Foundation

extension AnalyticsEvent {
    static func homeViewed() -> AnalyticsEvent {
        AnalyticsEvent(name: "home_viewed")
    }

    static func focusSetupViewed() -> AnalyticsEvent {
        AnalyticsEvent(name: "focus_setup_viewed")
    }

    static func focusSessionStarted(
        sessionType: String,
        durationMinutes: Int,
        entryPoint: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "focus_session_started",
            parameters: [
                "session_type": sessionType,
                "duration_minutes": durationMinutes,
                "entry_point": entryPoint
            ]
        )
    }

    static func focusSessionCompleted(
        sessionType: String,
        durationMinutes: Int,
        completedSuccessfully: Bool
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "focus_session_completed",
            parameters: [
                "session_type": sessionType,
                "duration_minutes": durationMinutes,
                "completed_successfully": completedSuccessfully
            ]
        )
    }

    static func focusSessionInterrupted(
        sessionType: String,
        durationMinutes: Int,
        interruptionReason: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "focus_session_interrupted",
            parameters: [
                "session_type": sessionType,
                "duration_minutes": durationMinutes,
                "interruption_reason": interruptionReason
            ]
        )
    }

    static func catchRevealViewed(
        catchCount: Int,
        bestRarity: String,
        sessionType: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "catch_reveal_viewed",
            parameters: [
                "catch_count": catchCount,
                "best_rarity": bestRarity,
                "session_type": sessionType
            ]
        )
    }

    static func fishSold(
        fishCount: Int,
        berriesEarned: Int,
        bestRarity: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "fish_sold",
            parameters: [
                "fish_count": fishCount,
                "berries_earned": berriesEarned,
                "best_rarity": bestRarity
            ]
        )
    }
}
