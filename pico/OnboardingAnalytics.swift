//
//  OnboardingAnalytics.swift
//  pico
//
//  Created by Codex on 17/5/2026.
//

import Foundation

struct OnboardingFlowContext: Equatable {
    let flowName: String
    let flowVersion: String
    let onboardingVariant: String
    let onboardingRunID: String

    init(
        flowName: String = "onboarding",
        flowVersion: String = "v1",
        onboardingVariant: String = "default",
        onboardingRunID: String = UUID().uuidString.lowercased()
    ) {
        self.flowName = flowName
        self.flowVersion = flowVersion
        self.onboardingVariant = onboardingVariant
        self.onboardingRunID = onboardingRunID
    }
}

enum OnboardingAction: String {
    case next
    case back
    case createAccount = "create_account"
    case logIn = "log_in"
    case signInWithGoogle = "sign_in_with_google"
    case signInWithApple = "sign_in_with_apple"
    case startFishing = "start_fishing"
    case reelItIn = "reel_it_in"
}

enum OnboardingSignupMethod: String {
    case apple
    case google
    case email
}

struct OnboardingPageDefinition: Equatable {
    let step: OnboardingStep
    let pageID: String
    let pageIndex: Int
    let pageCount: Int
    let pageType: String

    static let all: [OnboardingPageDefinition] = {
        let steps = OnboardingStep.ordered
        return steps.enumerated().map { index, step in
            OnboardingPageDefinition(
                step: step,
                pageID: pageID(for: step),
                pageIndex: index + 1,
                pageCount: steps.count,
                pageType: pageType(for: step)
            )
        }
    }()

    static func definition(for step: OnboardingStep) -> OnboardingPageDefinition {
        all.first { $0.step == step } ?? OnboardingPageDefinition(
            step: step,
            pageID: pageID(for: step),
            pageIndex: 1,
            pageCount: OnboardingStep.ordered.count,
            pageType: pageType(for: step)
        )
    }

    private static func pageID(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            return "welcome"
        case .displayName:
            return "display_name"
        case .rareFish:
            return "rare_fish"
        case .focusDuration:
            return "focus_duration"
        case .phoneUsage:
            return "phone_usage"
        case .focusIntent:
            return "focus_intent"
        case .focusGoal:
            return "focus_goal"
        case .productivityExperience:
            return "productivity_experience"
        case .focusBarrier:
            return "focus_barrier"
        case .whyOtherAppsFail:
            return "why_other_apps_fail"
        case .catchTeaser:
            return "catch_teaser"
        case .fishCelebration:
            return "fish_celebration"
        case .rewardCelebration:
            return "reward_celebration"
        case .focusWithFriends:
            return "focus_with_friends"
        case .authHandoff:
            return "auth_handoff"
        }
    }

    private static func pageType(for step: OnboardingStep) -> String {
        if step == .authHandoff {
            return "auth_handoff"
        }

        if step.isPreferenceStep {
            return "preference"
        }

        return "story"
    }
}

enum SignupPageID: String {
    case email = "signup_email"
    case firstName = "signup_first_name"
    case username = "signup_username"
    case password = "signup_password"
    case accountCreated = "account_created"
}

struct SignupPageDefinition: Equatable {
    let pageID: SignupPageID
    let pageIndex: Int
    let pageCount: Int
    let pageType: String

    static func definition(
        for step: SignupStep,
        onboardingContext: OnboardingFlowContext?
    ) -> SignupPageDefinition {
        definition(for: pageID(for: step), onboardingContext: onboardingContext)
    }

    static func accountCreated(onboardingContext: OnboardingFlowContext?) -> SignupPageDefinition {
        definition(for: .accountCreated, onboardingContext: onboardingContext)
    }

    private static func definition(
        for pageID: SignupPageID,
        onboardingContext: OnboardingFlowContext?
    ) -> SignupPageDefinition {
        let pages: [SignupPageID] = [
            .email,
            .firstName,
            .username,
            .password,
            .accountCreated
        ]
        let signupIndex = pages.firstIndex(of: pageID) ?? 0
        let onboardingCount = onboardingContext == nil ? 0 : OnboardingStep.ordered.count
        let totalCount = onboardingCount + pages.count

        return SignupPageDefinition(
            pageID: pageID,
            pageIndex: onboardingCount + signupIndex + 1,
            pageCount: totalCount,
            pageType: pageID == .accountCreated ? "synthetic_completion" : "signup"
        )
    }

    private static func pageID(for step: SignupStep) -> SignupPageID {
        switch step {
        case .email:
            return .email
        case .firstName:
            return .firstName
        case .username:
            return .username
        case .password:
            return .password
        }
    }
}

struct OnboardingAnalytics {
    let context: OnboardingFlowContext

    func trackStarted(step: OnboardingStep) {
        track(.onboardingStarted, step: step)
    }

    func trackScreenViewed(step: OnboardingStep) {
        let page = OnboardingPageDefinition.definition(for: step)
        track(
            .onboardingScreenViewed,
            step: step,
            parameters: [
                .screenIndex: .int(page.pageIndex),
                .screenName: .string(page.pageID)
            ]
        )
    }

    func trackActionTapped(_ action: OnboardingAction, step: OnboardingStep) {
        let page = OnboardingPageDefinition.definition(for: step)
        track(
            .onboardingActionTapped,
            step: step,
            parameters: [
                .screenName: .string(page.pageID),
                .actionName: .string(action.rawValue)
            ]
        )
    }

    func trackStepCompleted(step: OnboardingStep) {
        track(.onboardingStepCompleted, step: step)
    }

    func trackExited(step: OnboardingStep) {
        track(.onboardingExited, step: step)
    }

    private func track(
        _ id: AnalyticsEventID,
        step: OnboardingStep,
        parameters additionalParameters: [AnalyticsParameterKey: AnalyticsValue] = [:]
    ) {
        var parameters = dashboardParameters(for: step)
        additionalParameters.forEach { parameters[$0.key] = $0.value }
        Analytics.track(AnalyticsEvent(id: id, parameters: parameters))
    }

    private func dashboardParameters(for step: OnboardingStep) -> [AnalyticsParameterKey: AnalyticsValue] {
        let page = OnboardingPageDefinition.definition(for: step)
        return [
            .flowName: .string(context.flowName),
            .flowVersion: .string(context.flowVersion),
            .pageID: .string(page.pageID),
            .pageIndex: .int(page.pageIndex),
            .pageCount: .int(page.pageCount),
            .pageType: .string(page.pageType),
            .onboardingVariant: .string(context.onboardingVariant),
            .onboardingRunID: .string(context.onboardingRunID)
        ]
    }
}

struct SignupAnalytics {
    let entryPoint: String
    let onboardingContext: OnboardingFlowContext?

    func trackStarted(method: OnboardingSignupMethod = .email) {
        let page = SignupPageDefinition.definition(for: .email, onboardingContext: onboardingContext)
        track(
            .signupStarted,
            page: page,
            parameters: [
                .method: .string(method.rawValue),
                .signupMethod: .string(method.rawValue),
                .entryPoint: .string(entryPoint)
            ]
        )
    }

    func trackPageViewed(step: SignupStep) {
        track(.signupPageViewed, page: SignupPageDefinition.definition(for: step, onboardingContext: onboardingContext))
    }

    func trackStepCompleted(step: SignupStep) {
        track(.signupStepCompleted, page: SignupPageDefinition.definition(for: step, onboardingContext: onboardingContext))
    }

    func trackCompleted(method: OnboardingSignupMethod = .email) {
        track(
            .signupCompleted,
            page: SignupPageDefinition.accountCreated(onboardingContext: onboardingContext),
            parameters: [
                .method: .string(method.rawValue),
                .signupMethod: .string(method.rawValue),
                .entryPoint: .string(entryPoint)
            ]
        )
    }

    func trackOnboardingCompleted(method: OnboardingSignupMethod = .email) {
        guard onboardingContext != nil else { return }
        track(
            .onboardingCompleted,
            page: SignupPageDefinition.accountCreated(onboardingContext: onboardingContext),
            parameters: [
                .method: .string(method.rawValue),
                .signupMethod: .string(method.rawValue)
            ]
        )
    }

    private func track(
        _ id: AnalyticsEventID,
        page: SignupPageDefinition,
        parameters additionalParameters: [AnalyticsParameterKey: AnalyticsValue] = [:]
    ) {
        var parameters = pageParameters(for: page)
        if let onboardingContext {
            parameters[.flowName] = .string(onboardingContext.flowName)
            parameters[.flowVersion] = .string(onboardingContext.flowVersion)
            parameters[.onboardingVariant] = .string(onboardingContext.onboardingVariant)
            parameters[.onboardingRunID] = .string(onboardingContext.onboardingRunID)
        }
        additionalParameters.forEach { parameters[$0.key] = $0.value }
        Analytics.track(AnalyticsEvent(id: id, parameters: parameters))
    }

    private func pageParameters(for page: SignupPageDefinition) -> [AnalyticsParameterKey: AnalyticsValue] {
        [
            .pageID: .string(page.pageID.rawValue),
            .pageIndex: .int(page.pageIndex),
            .pageCount: .int(page.pageCount),
            .pageType: .string(page.pageType)
        ]
    }
}
