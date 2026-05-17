//
//  AnalyticsEvent.swift
//  pico
//
//  Created by Codex on 9/5/2026.
//

import Foundation

protocol AnalyticsEngine {
    func track(_ event: AnalyticsEvent)
    func setUserId(_ userId: String?)
    func setUserProperty(_ value: String?, forName name: AnalyticsUserPropertyKey)
}

struct AnalyticsEvent {
    let id: AnalyticsEventID
    let parameters: [AnalyticsParameterKey: AnalyticsValue]

    init(
        id: AnalyticsEventID,
        parameters: [AnalyticsParameterKey: AnalyticsValue] = [:]
    ) {
        self.id = id
        self.parameters = parameters
    }
}

enum AnalyticsEventID: String, CaseIterable {
    case onboardingStarted = "onboarding_started"
    case onboardingScreenViewed = "onboarding_screen_viewed"
    case onboardingActionTapped = "onboarding_action_tapped"
    case onboardingStepCompleted = "onboarding_step_completed"
    case onboardingExited = "onboarding_exited"
    case onboardingCompleted = "onboarding_completed"
    case signupStarted = "signup_started"
    case signupPageViewed = "signup_page_viewed"
    case signupStepCompleted = "signup_step_completed"
    case signupCompleted = "signup_completed"

    case homeViewed = "home_viewed"
    case focusSetupViewed = "focus_setup_viewed"
    case focusSessionStarted = "focus_session_started"
    case focusSessionCompleted = "focus_session_completed"
    case focusSessionInterrupted = "focus_session_interrupted"
    case catchRevealViewed = "catch_reveal_viewed"
    case fishSold = "fish_sold"

    case picoPlusRefreshSucceeded = "pico_plus_refresh_ok"
    case picoPlusRefreshFailed = "pico_plus_refresh_failed"
    case picoPlusPaywallTriggered = "pico_plus_paywall_trigger"
    case picoPlusPaywallFinished = "pico_plus_paywall_finish"
    case picoPlusPaywallFailed = "pico_plus_paywall_failed"
    case picoPlusGroupGateHit = "pico_plus_group_gate_hit"
    case picoPlusCalendarGateHit = "pico_plus_calendar_gate_hit"
    case picoPlusOnboardingGateHit = "pico_plus_onboarding_gate_hit"
    case picoPlusBondRewardGateHit = "pico_plus_bond_gate_hit"
    case picoPlusCosmeticGateHit = "pico_plus_cosmetic_gate_hit"
}

enum AnalyticsParameterKey: String, CaseIterable {
    case appVersion = "app_version"
    case buildNumber = "build_number"
    case platform

    case flowName = "flow_name"
    case flowVersion = "flow_version"
    case pageID = "page_id"
    case pageIndex = "page_index"
    case pageCount = "page_count"
    case pageType = "page_type"
    case onboardingVariant = "onboarding_variant"
    case onboardingRunID = "onboarding_run_id"
    case actionName = "action_name"
    case signupMethod = "signup_method"

    case screenIndex = "screen_index"
    case screenName = "screen_name"
    case method
    case entryPoint = "entry_point"

    case sessionType = "session_type"
    case durationMinutes = "duration_minutes"
    case completedSuccessfully = "completed_successfully"
    case interruptionReason = "interruption_reason"
    case catchCount = "catch_count"
    case bestRarity = "best_rarity"
    case fishCount = "fish_count"
    case berriesEarned = "berries_earned"

    case isActive = "is_active"
    case message
    case placement
    case source
    case outcome
    case currentMembers = "current_members"
    case selectedInvites = "selected_invites"
    case limit
    case residentID = "resident_id"
    case bondLevel = "bond_level"
    case itemID = "item_id"
    case itemType = "item_type"
    case itemKey = "item_key"
}

enum AnalyticsUserPropertyKey: String, CaseIterable {
    case appVersion = "app_version"
    case buildNumber = "build_number"
    case platform
}

enum AnalyticsValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

struct AnalyticsEventDefinition {
    let id: AnalyticsEventID
    let requiredParameters: Set<AnalyticsParameterKey>
    let optionalParameters: Set<AnalyticsParameterKey>

    init(
        id: AnalyticsEventID,
        requiredParameters: Set<AnalyticsParameterKey> = [],
        optionalParameters: Set<AnalyticsParameterKey> = []
    ) {
        self.id = id
        self.requiredParameters = requiredParameters
        self.optionalParameters = optionalParameters
    }
}

struct AnalyticsCatalog {
    static let shared = AnalyticsCatalog(definitions: [
        AnalyticsEventDefinition(
            id: .onboardingStarted,
            requiredParameters: onboardingDashboardParameters
        ),
        AnalyticsEventDefinition(
            id: .onboardingScreenViewed,
            requiredParameters: onboardingDashboardParameters.union([.screenIndex, .screenName])
        ),
        AnalyticsEventDefinition(
            id: .onboardingActionTapped,
            requiredParameters: onboardingDashboardParameters.union([.screenName, .actionName])
        ),
        AnalyticsEventDefinition(
            id: .onboardingStepCompleted,
            requiredParameters: onboardingDashboardParameters
        ),
        AnalyticsEventDefinition(
            id: .onboardingExited,
            requiredParameters: onboardingDashboardParameters
        ),
        AnalyticsEventDefinition(
            id: .onboardingCompleted,
            requiredParameters: onboardingDashboardParameters,
            optionalParameters: [.method, .signupMethod]
        ),
        AnalyticsEventDefinition(
            id: .signupStarted,
            requiredParameters: [.method, .entryPoint],
            optionalParameters: signupPageParameters.union(onboardingDashboardParameters).union([.signupMethod])
        ),
        AnalyticsEventDefinition(
            id: .signupPageViewed,
            requiredParameters: signupPageParameters,
            optionalParameters: onboardingDashboardParameters.union([.method, .signupMethod, .entryPoint])
        ),
        AnalyticsEventDefinition(
            id: .signupStepCompleted,
            requiredParameters: signupPageParameters,
            optionalParameters: onboardingDashboardParameters.union([.method, .signupMethod, .entryPoint])
        ),
        AnalyticsEventDefinition(
            id: .signupCompleted,
            requiredParameters: signupPageParameters.union([.method, .entryPoint]),
            optionalParameters: onboardingDashboardParameters.union([.signupMethod])
        ),

        AnalyticsEventDefinition(id: .homeViewed),
        AnalyticsEventDefinition(id: .focusSetupViewed),
        AnalyticsEventDefinition(
            id: .focusSessionStarted,
            requiredParameters: [.sessionType, .durationMinutes, .entryPoint]
        ),
        AnalyticsEventDefinition(
            id: .focusSessionCompleted,
            requiredParameters: [.sessionType, .durationMinutes, .completedSuccessfully]
        ),
        AnalyticsEventDefinition(
            id: .focusSessionInterrupted,
            requiredParameters: [.sessionType, .durationMinutes, .interruptionReason]
        ),
        AnalyticsEventDefinition(
            id: .catchRevealViewed,
            requiredParameters: [.catchCount, .bestRarity, .sessionType]
        ),
        AnalyticsEventDefinition(
            id: .fishSold,
            requiredParameters: [.fishCount, .berriesEarned, .bestRarity]
        ),

        AnalyticsEventDefinition(id: .picoPlusRefreshSucceeded, requiredParameters: [.isActive]),
        AnalyticsEventDefinition(id: .picoPlusRefreshFailed, requiredParameters: [.message]),
        AnalyticsEventDefinition(
            id: .picoPlusPaywallTriggered,
            requiredParameters: [.placement, .source]
        ),
        AnalyticsEventDefinition(
            id: .picoPlusPaywallFinished,
            requiredParameters: [.placement, .source, .outcome]
        ),
        AnalyticsEventDefinition(
            id: .picoPlusPaywallFailed,
            requiredParameters: [.placement, .source, .message]
        ),
        AnalyticsEventDefinition(
            id: .picoPlusGroupGateHit,
            requiredParameters: [.currentMembers, .selectedInvites, .limit]
        ),
        AnalyticsEventDefinition(id: .picoPlusCalendarGateHit),
        AnalyticsEventDefinition(id: .picoPlusOnboardingGateHit),
        AnalyticsEventDefinition(
            id: .picoPlusBondRewardGateHit,
            requiredParameters: [.residentID, .bondLevel]
        ),
        AnalyticsEventDefinition(
            id: .picoPlusCosmeticGateHit,
            requiredParameters: [.itemID, .itemType, .itemKey]
        )
    ])

    static let commonParameters: Set<AnalyticsParameterKey> = [
        .appVersion,
        .buildNumber,
        .platform
    ]

    private static let onboardingDashboardParameters: Set<AnalyticsParameterKey> = [
        .flowName,
        .flowVersion,
        .pageID,
        .pageIndex,
        .pageCount,
        .pageType,
        .onboardingVariant,
        .onboardingRunID
    ]

    private static let signupPageParameters: Set<AnalyticsParameterKey> = [
        .pageID,
        .pageIndex,
        .pageCount,
        .pageType
    ]

    private let definitionsByID: [AnalyticsEventID: AnalyticsEventDefinition]

    init(definitions: [AnalyticsEventDefinition]) {
        definitionsByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
    }

    func definition(for id: AnalyticsEventID) -> AnalyticsEventDefinition? {
        definitionsByID[id]
    }
}
