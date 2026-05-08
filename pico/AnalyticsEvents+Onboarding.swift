//
//  AnalyticsEvents+Onboarding.swift
//  pico
//
//  Created by Codex on 9/5/2026.
//

import Foundation

extension AnalyticsEvent {
    static func onboardingStarted() -> AnalyticsEvent {
        AnalyticsEvent(name: "onboarding_started")
    }

    static func onboardingScreenViewed(
        screenIndex: Int,
        screenName: String,
        onboardingVariant: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "onboarding_screen_viewed",
            parameters: [
                "screen_index": screenIndex,
                "screen_name": screenName,
                "onboarding_variant": onboardingVariant
            ]
        )
    }

    static func onboardingActionTapped(
        screenName: String,
        actionName: String,
        onboardingVariant: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "onboarding_action_tapped",
            parameters: [
                "screen_name": screenName,
                "action_name": actionName,
                "onboarding_variant": onboardingVariant
            ]
        )
    }

    static func signupStarted(method: String, entryPoint: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "signup_started",
            parameters: [
                "method": method,
                "entry_point": entryPoint
            ]
        )
    }

    static func signupCompleted(method: String, entryPoint: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "signup_completed",
            parameters: [
                "method": method,
                "entry_point": entryPoint
            ]
        )
    }

    static func onboardingCompleted() -> AnalyticsEvent {
        AnalyticsEvent(name: "onboarding_completed")
    }
}
