//
//  OnboardingViews.swift
//  pico
//
//  Created by Codex on 3/5/2026.
//

import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

struct AuthEntryView: View {
    let onGetStarted: () -> Void
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: PicoSpacing.largeSection) {
                Spacer(minLength: max(28, proxy.safeAreaInsets.top + 20))

                VStack(spacing: PicoSpacing.section) {
                    VStack(spacing: PicoSpacing.compact) {
                        PicoLogoImage()
                            .frame(width: 220, height: 96)

                        Text("Guilt-free focus")
                            .font(PicoTypography.bodySemibold)
                            .foregroundStyle(PicoColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: PicoSpacing.largeSection)

                VStack(spacing: PicoSpacing.iconTextGap) {
                    Button("Get started", action: onGetStarted)
                        .buttonStyle(PicoPrimaryButtonStyle())

                    Button("Already have an account?", action: onLogin)
                        .buttonStyle(PicoSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, PicoSpacing.standard)
            .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

private struct PicoLogoImage: View {
    private let image = [
        "Icons/pico_logo",
        "Icons/pico_logo.png",
        "pico_logo",
        "pico_logo.png"
    ]
    .lazy
    .compactMap { UIImage(named: $0) }
    .first

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Pico")
                    .font(PicoTypography.screenTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pico"))
    }
}

struct OnboardingSequenceView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let onBackToEntry: () -> Void
    let onSignup: (String) -> Void
    let onLogin: (String) -> Void

    @State private var currentStep: OnboardingStep
    @State private var hasTrackedOnboardingStart = false
    @State private var lastTrackedScreenStep: OnboardingStep?
    @State private var selectedPhoneUsageHours = 4
    @State private var selectedFocusIntents: Set<OnboardingFocusIntent> = []
    @State private var selectedFocusGoal: OnboardingFocusGoal?
    @State private var selectedFocusBarriers: Set<OnboardingFocusBarrier> = []
    @State private var hasTriedProductivityApps: Bool?
    @State private var onboardingDisplayName: String
    @State private var onboardingCelebrationFish = OnboardingRareFreshwaterFish.random()
    @State private var appleSignInNonce: String?
    @State private var hasTrackedAppleSignupCompletion = false
    @State private var hasTrackedAppleOnboardingCompletion = false
    @State private var hasTrackedGoogleSignupCompletion = false
    @State private var hasTrackedGoogleOnboardingCompletion = false
    @State private var isPresentingOnboardingPaywall = false
    @FocusState private var isDisplayNameFocused: Bool

    init(
        initialStep: OnboardingStep = OnboardingStep.ordered.first ?? .welcome,
        initialDisplayName: String = "",
        onBackToEntry: @escaping () -> Void,
        onSignup: @escaping (String) -> Void,
        onLogin: @escaping (String) -> Void
    ) {
        self.onBackToEntry = onBackToEntry
        self.onSignup = onSignup
        self.onLogin = onLogin
        _currentStep = State(initialValue: initialStep)
        _onboardingDisplayName = State(initialValue: initialDisplayName)
    }

    private let onboardingVariant = "default"

    private var currentIndex: Int {
        OnboardingStep.ordered.firstIndex(of: currentStep) ?? 0
    }

    private var currentProgressIndex: Int {
        OnboardingStep.progressSteps.firstIndex(of: currentStep) ?? currentIndex
    }

    private var primaryCTATitle: String {
        if currentStep.isPreferenceStep {
            return "Continue"
        }

        switch currentStep {
        case .displayName:
            return "Create my character"
        case .rareFish:
            return "Start fishing"
        case .catchTeaser:
            return "Reel it in!"
        case .focusWithFriends:
            return "Get started"
        case .authHandoff:
            return "Create an account"
        default:
            return "Continue"
        }
    }

    private var primaryCTAAnalyticsActionName: String {
        switch currentStep {
        case .rareFish:
            "start_fishing"
        case .catchTeaser:
            "reel_it_in"
        case .welcome, .displayName, .focusDuration, .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience, .whyOtherAppsFail, .fishCelebration, .rewardCelebration, .focusWithFriends, .authHandoff:
            "next"
        }
    }

    private var normalizedDisplayName: String {
        onboardingDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPrimaryCTAEnabled: Bool {
        guard !isPresentingOnboardingPaywall else { return false }

        return switch currentStep {
        case .displayName:
            (1...40).contains(normalizedDisplayName.count)
        case .focusIntent:
            !selectedFocusIntents.isEmpty
        case .focusGoal:
            selectedFocusGoal != nil
        case .focusBarrier:
            !selectedFocusBarriers.isEmpty
        case .productivityExperience:
            hasTriedProductivityApps != nil
        case .welcome, .focusDuration, .phoneUsage, .rareFish, .whyOtherAppsFail, .catchTeaser, .fishCelebration, .rewardCelebration, .focusWithFriends, .authHandoff:
            true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = min(max(proxy.size.height * 0.42, 320), 430)

            VStack(spacing: 0) {
                if currentStep.showsProgressHeader {
                    OnboardingProgressHeader(
                        currentIndex: currentProgressIndex,
                        totalCount: OnboardingStep.progressSteps.count,
                        onBack: goBack
                    )
                }

                VStack(spacing: 0) {
                    if currentStep.isPreferenceStep {
                        Spacer(minLength: PicoSpacing.compact)

                        OnboardingSetupStepContent(
                            step: currentStep,
                            selectedPhoneUsageHours: $selectedPhoneUsageHours,
                            selectedFocusIntents: $selectedFocusIntents,
                            selectedFocusGoal: $selectedFocusGoal,
                            selectedFocusBarriers: $selectedFocusBarriers,
                            hasTriedProductivityApps: $hasTriedProductivityApps
                        )

                        Spacer(minLength: PicoSpacing.compact)

                        Button(action: handlePrimaryAction) {
                            OnboardingPrimaryCTALabel(title: primaryCTATitle)
                        }
                        .buttonStyle(PicoPrimaryButtonStyle())
                        .disabled(!isPrimaryCTAEnabled)
                    } else if currentStep == .authHandoff {
                        Spacer(minLength: PicoSpacing.compact)

                        VStack(spacing: PicoSpacing.largeSection) {
                            OnboardingStoryStepTitle(
                                currentStep: currentStep
                            )

                            OnboardingStoryStepActions(
                                currentStep: currentStep,
                                primaryCTATitle: primaryCTATitle,
                                handlePrimaryAction: handlePrimaryAction,
                                handleSignupAction: handleSignupAction,
                                handleGoogleSignIn: handleGoogleSignIn,
                                handleAppleSignInRequest: handleAppleSignInRequest,
                                handleAppleSignInCompletion: handleAppleSignInCompletion,
                                handleLoginAction: handleLoginAction,
                                isLoading: sessionStore.isLoading
                            )
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: PicoSpacing.compact)
                    } else if currentStep.usesIslandVisual {
                        GeometryReader { contentProxy in
                            let headerSlotHeight = OnboardingStoryLayout.islandHeaderSlotHeight
                            let visualCenterY = contentProxy.size.height * OnboardingStoryLayout.islandVisualCenterRatio
                            let headerCenterY = visualCenterY
                                - (visualHeight / 2)
                                - OnboardingStoryLayout.islandHeaderVisualGap
                                - (headerSlotHeight / 2)

                            if currentStep == .displayName {
                                ZStack(alignment: .top) {
                                    VStack(spacing: PicoSpacing.section) {
                                        OnboardingStoryStepTitle(
                                            currentStep: currentStep
                                        )

                                        OnboardingDisplayNameInput(
                                            displayName: $onboardingDisplayName,
                                            isFocused: $isDisplayNameFocused,
                                            handleSubmit: handlePrimaryAction
                                        )
                                    }
                                    .padding(.top, max(PicoSpacing.section, contentProxy.size.height * 0.08))
                                    .frame(maxWidth: .infinity)
                                    .zIndex(1)

                                    VStack(spacing: PicoSpacing.compact) {
                                        Spacer(minLength: OnboardingStoryLayout.displayNameTopContentReservedHeight)

                                        storyVisual(for: currentStep, visualHeight: visualHeight)
                                            .frame(width: contentProxy.size.width, height: visualHeight)
                                            .allowsHitTesting(false)

                                        Spacer(minLength: PicoSpacing.compact)

                                        OnboardingStoryStepActions(
                                            currentStep: currentStep,
                                            primaryCTATitle: primaryCTATitle,
                                            handlePrimaryAction: handlePrimaryAction,
                                            handleSignupAction: handleSignupAction,
                                            handleGoogleSignIn: handleGoogleSignIn,
                                            handleAppleSignInRequest: handleAppleSignInRequest,
                                            handleAppleSignInCompletion: handleAppleSignInCompletion,
                                            handleLoginAction: handleLoginAction
                                        )
                                        .disabled(!isPrimaryCTAEnabled)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ZStack(alignment: .top) {
                                    storyVisual(for: currentStep, visualHeight: visualHeight)
                                        .frame(width: contentProxy.size.width, height: visualHeight)
                                        .position(x: contentProxy.size.width / 2, y: visualCenterY)

                                    VStack(spacing: 0) {
                                        OnboardingStoryStepTitle(
                                            currentStep: currentStep
                                        )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: headerSlotHeight, alignment: .bottom)
                                    .position(x: contentProxy.size.width / 2, y: headerCenterY)

                                    VStack(spacing: 0) {
                                        Spacer(minLength: 0)

                                        OnboardingStoryStepActions(
                                            currentStep: currentStep,
                                            primaryCTATitle: primaryCTATitle,
                                            handlePrimaryAction: handlePrimaryAction,
                                            handleSignupAction: handleSignupAction,
                                            handleGoogleSignIn: handleGoogleSignIn,
                                            handleAppleSignInRequest: handleAppleSignInRequest,
                                            handleAppleSignInCompletion: handleAppleSignInCompletion,
                                            handleLoginAction: handleLoginAction
                                        )
                                        .disabled(!isPrimaryCTAEnabled)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    } else {
                        Spacer(minLength: PicoSpacing.compact)

                        VStack(spacing: currentStep == .whyOtherAppsFail ? PicoSpacing.section : 0) {
                            OnboardingStoryStepTitle(
                                currentStep: currentStep
                            )
                            storyVisual(for: currentStep, visualHeight: visualHeight)
                        }

                        Spacer(minLength: PicoSpacing.compact)

                        OnboardingStoryStepActions(
                            currentStep: currentStep,
                            primaryCTATitle: primaryCTATitle,
                            handlePrimaryAction: handlePrimaryAction,
                            handleSignupAction: handleSignupAction,
                            handleGoogleSignIn: handleGoogleSignIn,
                            handleAppleSignInRequest: handleAppleSignInRequest,
                            handleAppleSignInCompletion: handleAppleSignInCompletion,
                            handleLoginAction: handleLoginAction
                        )
                        .disabled(!isPrimaryCTAEnabled)
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.light)
        .onAppear {
            trackOnboardingStartIfNeeded()
            trackCurrentScreenIfNeeded()
        }
        .onChange(of: currentStep) {
            if currentStep != .displayName {
                isDisplayNameFocused = false
            }
            trackCurrentScreenIfNeeded()
        }
    }

    private func handlePrimaryAction() {
        guard isPrimaryCTAEnabled else { return }

        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: primaryCTAAnalyticsActionName,
            onboardingVariant: onboardingVariant
        ))

        if currentStep == .focusWithFriends {
            presentOnboardingCompletePaywall()
            return
        }

        isDisplayNameFocused = false
        goForward()
    }

    private func handleSignupAction() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "create_account",
            onboardingVariant: onboardingVariant
        ))
        onSignup(normalizedDisplayName)
    }

    private func handleLoginAction() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "log_in",
            onboardingVariant: onboardingVariant
        ))
        onLogin(normalizedDisplayName)
    }

    private func handleGoogleSignIn() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "sign_in_with_google",
            onboardingVariant: onboardingVariant
        ))

        Task {
            await sessionStore.signInWithGoogle()
            if sessionStore.session != nil {
                trackGoogleSignupCompletionIfNeeded()
                trackGoogleOnboardingCompletionIfNeeded()
            }
        }
    }

    private func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "sign_in_with_apple",
            onboardingVariant: onboardingVariant
        ))

        let nonce = AppleSignInNonce.random()
        appleSignInNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = AppleSignInNonce.sha256(nonce)
        sessionStore.notice = nil
    }

    private func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                sessionStore.notice = "Sign in with Apple did not return a valid identity token."
                return
            }

            Task {
                await sessionStore.signInWithApple(idToken: idToken, nonce: appleSignInNonce)
                if sessionStore.session != nil {
                    trackAppleSignupCompletionIfNeeded()
                    trackAppleOnboardingCompletionIfNeeded()
                }
            }
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            sessionStore.notice = nil
        }
    }

    private func trackAppleSignupCompletionIfNeeded() {
        guard !hasTrackedAppleSignupCompletion else { return }
        hasTrackedAppleSignupCompletion = true
        AnalyticsService.track(.signupCompleted(method: "apple", entryPoint: "onboarding"))
    }

    private func trackAppleOnboardingCompletionIfNeeded() {
        guard !hasTrackedAppleOnboardingCompletion else { return }
        hasTrackedAppleOnboardingCompletion = true
        AnalyticsService.track(.onboardingCompleted())
    }

    private func trackGoogleSignupCompletionIfNeeded() {
        guard !hasTrackedGoogleSignupCompletion else { return }
        hasTrackedGoogleSignupCompletion = true
        AnalyticsService.track(.signupCompleted(method: "google", entryPoint: "onboarding"))
    }

    private func trackGoogleOnboardingCompletionIfNeeded() {
        guard !hasTrackedGoogleOnboardingCompletion else { return }
        hasTrackedGoogleOnboardingCompletion = true
        AnalyticsService.track(.onboardingCompleted())
    }

    private func goForward() {
        let steps = OnboardingStep.ordered
        guard currentIndex < steps.index(before: steps.endIndex) else {
            onSignup(normalizedDisplayName)
            return
        }

        if currentStep == .catchTeaser {
            onboardingCelebrationFish = OnboardingRareFreshwaterFish.random()
        }

        currentStep = steps[currentIndex + 1]
    }

    private func presentOnboardingCompletePaywall() {
        guard !isPresentingOnboardingPaywall else { return }

        isPresentingOnboardingPaywall = true
        Task { @MainActor in
            await picoPlusStore.presentPaywall(
                source: .onboardingComplete(placement: .onboardingComplete),
                authSession: sessionStore.session
            )
            isPresentingOnboardingPaywall = false
            goForward()
        }
    }

    private func goBack() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "back",
            onboardingVariant: onboardingVariant
        ))

        guard currentIndex > 0 else {
            onBackToEntry()
            return
        }

        currentStep = OnboardingStep.ordered[currentIndex - 1]
    }

    private func trackOnboardingStartIfNeeded() {
        guard !hasTrackedOnboardingStart else { return }
        hasTrackedOnboardingStart = true
        AnalyticsService.track(.onboardingStarted())
    }

    private func trackCurrentScreenIfNeeded() {
        guard lastTrackedScreenStep != currentStep else { return }
        lastTrackedScreenStep = currentStep
        AnalyticsService.track(.onboardingScreenViewed(
            screenIndex: currentIndex + 1,
            screenName: currentStep.analyticsName,
            onboardingVariant: onboardingVariant
        ))
    }

    @ViewBuilder
    private func storyVisual(for step: OnboardingStep, visualHeight: CGFloat) -> some View {
        switch step {
        case .welcome:
            StartFishingOnboardingVisual(isFishing: false, showsAvatar: false)
                .frame(height: visualHeight)
        case .displayName:
            StartFishingOnboardingVisual(isFishing: false, showsAvatar: false)
                .frame(height: visualHeight)
        case .rareFish:
            StartFishingOnboardingVisual(isFishing: false)
                .frame(height: visualHeight)
        case .focusDuration:
            StartFishingOnboardingVisual(isFishing: true)
                .frame(height: visualHeight)
        case .whyOtherAppsFail:
            OnboardingWhatDoesntWorkCardsVisual()
        case .catchTeaser:
            StartFishingOnboardingVisual(isFishing: true)
                .frame(height: visualHeight)
        case .fishCelebration:
            OnboardingFishCelebrationVisual(fish: onboardingCelebrationFish)
                .frame(height: min(visualHeight, 330))
        case .rewardCelebration:
            OnboardingMovingIslandVisual()
                .frame(height: visualHeight)
        case .focusWithFriends:
            OnboardingFriendsIslandVisual()
                .frame(height: visualHeight)
        case .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience, .authHandoff:
            EmptyView()
        }
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case displayName
    case rareFish
    case focusDuration
    case phoneUsage
    case focusIntent
    case focusGoal
    case focusBarrier
    case productivityExperience
    case whyOtherAppsFail
    case catchTeaser
    case fishCelebration
    case rewardCelebration
    case focusWithFriends
    case authHandoff

    static let ordered: [OnboardingStep] = [
        .welcome,
        .displayName,
        .rareFish,
        .focusDuration,
        .phoneUsage,
        .focusIntent,
        .focusGoal,
        .productivityExperience,
        .focusBarrier,
        .whyOtherAppsFail,
        .catchTeaser,
        .fishCelebration,
        .rewardCelebration,
        .focusWithFriends,
        .authHandoff
    ]

    static var progressSteps: [OnboardingStep] {
        ordered.filter(\.showsProgressHeader)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:
            "Welcome to Pico!"
        case .displayName:
            "First off, what should we call you?"
        case .rareFish:
            "Catch rare fish as you focus"
        case .focusDuration:
            "Let's get to know you while we wait"
        case .phoneUsage:
            "How much time do you spend on your phone?"
        case .focusIntent:
            "What do you want to focus on instead?"
        case .focusGoal:
            "How much focus do you want back?"
        case .focusBarrier:
            "What's stopping you?"
        case .productivityExperience:
            "Have you tried other apps?"
        case .whyOtherAppsFail:
            "What doesn't work"
        case .catchTeaser:
            "You've caught something!"
        case .fishCelebration:
            "You caught a rare fish!"
        case .rewardCelebration:
            "Small wins create long term habits"
        case .focusWithFriends:
            "Focus better with friends"
        case .authHandoff:
            "Create an account"
        }
    }

    var placeholderText: String {
        switch self {
        case .welcome:
            "Your guilt-free focus island"
        case .displayName:
            ""
        case .rareFish:
            ""
        case .focusDuration:
            "We'll see what you catch later on"
        case .phoneUsage:
            ""
        case .focusIntent:
            ""
        case .focusGoal:
            "You can always change this goal later"
        case .focusBarrier:
            ""
        case .productivityExperience:
            ""
        case .whyOtherAppsFail:
            ""
        case .catchTeaser:
            ""
        case .fishCelebration:
            ""
        case .rewardCelebration:
            ""
        case .focusWithFriends:
            ""
        case .authHandoff:
            ""
        }
    }

    var analyticsName: String {
        switch self {
        case .welcome:
            "welcome"
        case .displayName:
            "display_name"
        case .rareFish:
            "rare_fish"
        case .focusDuration:
            "focus_duration"
        case .phoneUsage:
            "phone_usage"
        case .focusIntent:
            "focus_intent"
        case .focusGoal:
            "focus_goal"
        case .focusBarrier:
            "focus_barrier"
        case .productivityExperience:
            "productivity_experience"
        case .whyOtherAppsFail:
            "why_other_apps_fail"
        case .catchTeaser:
            "catch_teaser"
        case .fishCelebration:
            "fish_celebration"
        case .rewardCelebration:
            "reward_celebration"
        case .focusWithFriends:
            "focus_with_friends"
        case .authHandoff:
            "auth_handoff"
        }
    }

    var isPreferenceStep: Bool {
        switch self {
        case .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience:
            true
        case .welcome, .displayName, .rareFish, .focusDuration, .whyOtherAppsFail, .catchTeaser, .fishCelebration, .rewardCelebration, .focusWithFriends, .authHandoff:
            false
        }
    }

    var usesIslandVisual: Bool {
        switch self {
        case .welcome, .displayName, .rareFish, .focusDuration, .catchTeaser, .rewardCelebration, .focusWithFriends:
            true
        case .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience, .whyOtherAppsFail, .fishCelebration, .authHandoff:
            false
        }
    }

    var showsProgressHeader: Bool {
        self != .authHandoff
    }

}

private enum OnboardingStoryLayout {
    static let islandHeaderSlotHeight: CGFloat = 92
    static let islandDisplayNameHeaderSlotHeight: CGFloat = 158
    static let displayNameTopContentReservedHeight: CGFloat = 188
    static let islandHeaderVisualGap: CGFloat = 12
    static let islandVisualCenterRatio: CGFloat = 0.5
}

private enum OnboardingFocusIntent: String, CaseIterable, Identifiable {
    case studying = "Studying"
    case friendsFamily = "Friends/Family"
    case work = "Work"
    case creativeProjects = "Creative projects"
    case reading = "Reading"
    case exercise = "Exercise"
    case fitness = "Fitness"
    case somethingElse = "Something else"

    var id: String { rawValue }
}

private enum OnboardingFocusGoal: String, CaseIterable, Identifiable {
    case tenMinutes = "10mins"
    case twentyFiveMinutes = "25mins"
    case oneHourPlus = "1hour+"

    var id: String { rawValue }
}

private enum OnboardingFocusBarrier: String, CaseIterable, Identifiable {
    case hardToFocusAlone = "It's hard to focus alone"
    case blockingAppsStopsWorking = "Blocking apps stops working"
    case slowlyQuit = "I start, then slowly quit"
    case loseMotivationQuickly = "I lose motivation quickly"
    case distractedEasily = "I get distracted easily"

    var id: String { rawValue }
}

private struct OnboardingSetupStepContent: View {
    let step: OnboardingStep
    @Binding var selectedPhoneUsageHours: Int
    @Binding var selectedFocusIntents: Set<OnboardingFocusIntent>
    @Binding var selectedFocusGoal: OnboardingFocusGoal?
    @Binding var selectedFocusBarriers: Set<OnboardingFocusBarrier>
    @Binding var hasTriedProductivityApps: Bool?

    private let optionColumns = [
        GridItem(.adaptive(minimum: 132), spacing: PicoSpacing.iconTextGap)
    ]

    var body: some View {
        VStack(spacing: PicoSpacing.largeSection) {
            switch step {
            case .phoneUsage:
                phoneUsageContent
            case .focusIntent:
                focusIntentContent
            case .focusGoal:
                focusGoalContent
            case .focusBarrier:
                focusBarrierContent
            case .productivityExperience:
                productivityExperienceContent
            case .welcome, .displayName, .rareFish, .focusDuration, .whyOtherAppsFail, .catchTeaser, .fishCelebration, .rewardCelebration, .focusWithFriends, .authHandoff:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneUsageContent: some View {
        VStack(spacing: PicoSpacing.section) {
            VStack(spacing: PicoSpacing.compact) {
                OnboardingQuestionTitle(title: step.title)

                Text("Don't worry, we don't judge")
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PicoSpacing.standard)

            OnboardingPhoneUsageSlider(
                selectedHours: $selectedPhoneUsageHours
            )
        }
    }

    private var focusIntentContent: some View {
        VStack(spacing: PicoSpacing.section) {
            OnboardingQuestionTitle(title: step.title)

            LazyVGrid(columns: optionColumns, spacing: PicoSpacing.iconTextGap) {
                ForEach(OnboardingFocusIntent.allCases) { intent in
                    OnboardingChoiceButton(
                        title: intent.rawValue,
                        isSelected: selectedFocusIntents.contains(intent)
                    ) {
                        toggleFocusIntent(intent)
                    }
                }
            }
        }
    }

    private func toggleFocusIntent(_ intent: OnboardingFocusIntent) {
        if selectedFocusIntents.contains(intent) {
            selectedFocusIntents.remove(intent)
        } else {
            selectedFocusIntents.insert(intent)
        }
    }

    private var focusGoalContent: some View {
        VStack(spacing: PicoSpacing.section) {
            OnboardingQuestionTitle(title: step.title)

            Text(step.placeholderText)
                .font(PicoTypography.body)
                .foregroundStyle(PicoColors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: PicoSpacing.iconTextGap) {
                ForEach(OnboardingFocusGoal.allCases) { goal in
                    OnboardingChoiceButton(
                        title: goal.rawValue,
                        isSelected: selectedFocusGoal == goal
                    ) {
                        selectedFocusGoal = goal
                    }
                }
            }
        }
    }

    private var focusBarrierContent: some View {
        VStack(spacing: PicoSpacing.section) {
            OnboardingQuestionTitle(title: step.title)

            VStack(spacing: PicoSpacing.iconTextGap) {
                ForEach(OnboardingFocusBarrier.allCases) { barrier in
                    OnboardingChoiceButton(
                        title: barrier.rawValue,
                        isSelected: selectedFocusBarriers.contains(barrier)
                    ) {
                        toggleFocusBarrier(barrier)
                    }
                }
            }
        }
    }

    private func toggleFocusBarrier(_ barrier: OnboardingFocusBarrier) {
        if selectedFocusBarriers.contains(barrier) {
            selectedFocusBarriers.remove(barrier)
        } else {
            selectedFocusBarriers.insert(barrier)
        }
    }

    private var productivityExperienceContent: some View {
        VStack(spacing: PicoSpacing.section) {
            OnboardingQuestionTitle(title: step.title)

            VStack(spacing: PicoSpacing.iconTextGap) {
                OnboardingChoiceButton(
                    title: "Yes",
                    isSelected: hasTriedProductivityApps == true
                ) {
                    hasTriedProductivityApps = true
                }

                OnboardingChoiceButton(
                    title: "No",
                    isSelected: hasTriedProductivityApps == false
                ) {
                    hasTriedProductivityApps = false
                }
            }
        }
    }
}

private struct OnboardingStoryStepTitle: View {
    let currentStep: OnboardingStep

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            if currentStep != .welcome && currentStep != .rareFish && currentStep != .rewardCelebration {
                if currentStep == .focusWithFriends {
                    OnboardingFocusWithFriendsTitle()
                } else if currentStep == .authHandoff {
                    OnboardingAuthHandoffTitle()
                } else {
                    Text(currentStep.title)
                        .font(PicoTypography.sectionTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if currentStep == .welcome {
                OnboardingWelcomeTitle()
            } else if currentStep == .rareFish {
                OnboardingRareFishTitle()
            } else if currentStep == .rewardCelebration {
                OnboardingRewardCelebrationTitle()
            } else if currentStep != .focusWithFriends && currentStep != .authHandoff && !currentStep.placeholderText.isEmpty {
                Text(currentStep.placeholderText)
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingStoryStepActions: View {
    let currentStep: OnboardingStep
    let primaryCTATitle: String
    let handlePrimaryAction: () -> Void
    let handleSignupAction: () -> Void
    let handleGoogleSignIn: () -> Void
    let handleAppleSignInRequest: (ASAuthorizationAppleIDRequest) -> Void
    let handleAppleSignInCompletion: (Result<ASAuthorization, Error>) -> Void
    let handleLoginAction: () -> Void
    var isLoading = false

    var body: some View {
        VStack(spacing: PicoSpacing.iconTextGap) {
            if currentStep == .authHandoff {
                VStack(spacing: PicoSpacing.iconTextGap) {
                    Button("Create account", action: handleSignupAction)
                        .buttonStyle(PicoPrimaryButtonStyle())

                    PicoAuthDivider()
                        .padding(.top, PicoSpacing.compact)

                    PicoGoogleSignInButton(
                        title: "Sign in with Google",
                        isLoading: isLoading,
                        action: handleGoogleSignIn
                    )

                    PicoAppleSignInButton(
                        isLoading: isLoading,
                        onRequest: handleAppleSignInRequest,
                        onCompletion: handleAppleSignInCompletion
                    )

                    HStack(spacing: PicoSpacing.tiny) {
                        Text("Already have an account?")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)

                        Button("Log in", action: handleLoginAction)
                            .font(PicoTypography.captionSemibold)
                            .foregroundStyle(PicoColors.primary)
                            .buttonStyle(.plain)
                    }
                }
            } else if currentStep == .catchTeaser {
                OnboardingReelButton(title: primaryCTATitle, action: handlePrimaryAction)
            } else {
                if currentStep == .whyOtherAppsFail {
                    Text("Pico takes a different approach")
                        .font(PicoTypography.body)
                        .foregroundStyle(PicoColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: handlePrimaryAction) {
                    OnboardingPrimaryCTALabel(
                        title: primaryCTATitle,
                        showsFishingPole: currentStep == .rareFish
                    )
                }
                .buttonStyle(PicoPrimaryButtonStyle())
            }
        }
    }
}

private enum AppleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

private struct OnboardingQuestionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PicoTypography.sectionTitle)
            .foregroundStyle(PicoColors.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OnboardingChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.iconTextGap) {
                Text(title)
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: PicoSpacing.compact)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(PicoTypography.symbol(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? PicoColors.primary : PicoColors.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(PicoColors.softSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .stroke(isSelected ? PicoColors.primary : PicoColors.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OnboardingPhoneUsageSlider: View {
    @Binding var selectedHours: Int

    private let hourRange = 0...12
    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 32

    private var progress: CGFloat {
        CGFloat(selectedHours - hourRange.lowerBound) / CGFloat(hourRange.upperBound - hourRange.lowerBound)
    }

    private var hourText: String {
        if selectedHours == 0 {
            return "Less than 1 hour"
        }

        if selectedHours == 1 {
            return "1 hour"
        }

        return "\(selectedHours) hours"
    }

    var body: some View {
        VStack(spacing: PicoSpacing.section) {
            Text(hourText)
                .font(PicoTypography.cardTitle)
                .foregroundStyle(PicoColors.textPrimary)
                .multilineTextAlignment(.center)

            GeometryReader { proxy in
                let usableWidth = max(proxy.size.width - thumbSize, 1)
                let thumbX = usableWidth * progress

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PicoColors.softSurface)
                        .frame(height: trackHeight)

                    Capsule(style: .continuous)
                        .fill(PicoColors.primary)
                        .frame(width: thumbX + thumbSize / 2, height: trackHeight)

                    Circle()
                        .fill(PicoColors.surface)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(
                            Circle()
                                .stroke(PicoColors.primary, lineWidth: 2)
                        )
                        .shadow(color: PicoShadow.raisedCardColor, radius: 6, x: 0, y: 3)
                        .offset(x: thumbX)
                }
                .frame(height: thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            updateSelection(at: gesture.location.x, usableWidth: usableWidth)
                        }
                )
            }
            .frame(height: thumbSize)

            HStack {
                Text("0h")
                Spacer()
                Text("6h")
                Spacer()
                Text("12h+")
            }
            .font(PicoTypography.captionSemibold)
            .foregroundStyle(PicoColors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily phone usage"))
        .accessibilityValue(Text(hourText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                moveSelection(by: 1)
            case .decrement:
                moveSelection(by: -1)
            @unknown default:
                break
            }
        }
    }

    private func updateSelection(at xPosition: CGFloat, usableWidth: CGFloat) {
        let rawProgress = min(max(Double((xPosition - thumbSize / 2) / usableWidth), 0), 1)
        let hours = Int((rawProgress * Double(hourRange.upperBound - hourRange.lowerBound)).rounded()) + hourRange.lowerBound
        selectedHours = min(max(hours, hourRange.lowerBound), hourRange.upperBound)
    }

    private func moveSelection(by offset: Int) {
        selectedHours = min(max(selectedHours + offset, hourRange.lowerBound), hourRange.upperBound)
    }
}

private struct OnboardingWhatDoesntWorkCardsVisual: View {
    private let cards = [
        OnboardingWhatDoesntWorkCardContent(
            title: "Blockers",
            body: "Creates guilt when you slip up and reduces motivation",
            symbol: "exclamationmark.shield"
        ),
        OnboardingWhatDoesntWorkCardContent(
            title: "Timers without rewards",
            body: "Makes focus feel stressful",
            symbol: "timer"
        ),
        OnboardingWhatDoesntWorkCardContent(
            title: "Strict routines",
            body: "Get boring before they become habits",
            symbol: "calendar"
        )
    ]

    var body: some View {
        VStack(spacing: PicoSpacing.iconTextGap) {
            ForEach(cards) { card in
                OnboardingWhatDoesntWorkCard(content: card)
            }
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct OnboardingWhatDoesntWorkCardContent: Identifiable {
    let title: String
    let body: String
    let symbol: String

    var id: String { title }
}

private struct OnboardingWhatDoesntWorkCard: View {
    let content: OnboardingWhatDoesntWorkCardContent

    var body: some View {
        HStack(spacing: PicoSpacing.standard) {
            Image(systemName: content.symbol)
                .font(PicoTypography.symbol(size: 24, weight: .semibold))
                .foregroundStyle(PicoColors.error)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text(content.title)
                    .font(PicoTypography.primaryLabelSemibold)
                    .foregroundStyle(PicoColors.error)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.body)
                    .font(PicoTypography.body)
                    .foregroundStyle(PicoColors.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PicoSpacing.compact)
        }
        .padding(PicoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                .fill(PicoColors.softSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PicoRadius.small, style: .continuous)
                .stroke(PicoColors.border, lineWidth: 1)
        )
        .accessibilityLabel(Text("\(content.title). \(content.body)"))
    }
}

private struct OnboardingDisplayNameInput: View {
    @Binding var displayName: String
    let isFocused: FocusState<Bool>.Binding
    let handleSubmit: () -> Void

    var body: some View {
        TextField(
            "",
            text: $displayName,
            prompt: Text("Name").foregroundStyle(PicoColors.textMuted)
        )
        .textContentType(.name)
        .submitLabel(.continue)
        .foregroundStyle(PicoColors.textPrimary)
        .authFieldStyle()
        .focused(isFocused)
        .onSubmit(handleSubmit)
    }
}

private struct OnboardingRareFreshwaterFish: Equatable {
    let id: FishID
    let displayName: String
    let assetName: String

    var accessibilityLabel: String {
        "You caught a \(displayName.lowercased())"
    }

    static func random() -> OnboardingRareFreshwaterFish {
        all.randomElement() ?? all[0]
    }

    private static let all: [OnboardingRareFreshwaterFish] = [
        OnboardingRareFreshwaterFish(
            id: FishID(rawValue: "angelfish"),
            displayName: "Rare Angelfish",
            assetName: "freshwater/rare_angelfish"
        ),
        OnboardingRareFreshwaterFish(
            id: FishID(rawValue: "leopoldi"),
            displayName: "Rare Leopoldi",
            assetName: "freshwater/rare_leopoldi"
        ),
        OnboardingRareFreshwaterFish(
            id: FishID(rawValue: "sturgeon"),
            displayName: "Rare Sturgeon",
            assetName: "freshwater/rare_sturgeon"
        )
    ]
}

private struct OnboardingFishCelebrationVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fish: OnboardingRareFreshwaterFish

    var body: some View {
        ZStack {
            OnboardingConfettiVisual(reduceMotion: reduceMotion)
                .frame(width: 360, height: 280)
                .allowsHitTesting(false)

            VStack(spacing: PicoSpacing.iconTextGap) {
                OnboardingFishImage(fish: fish)
                    .frame(width: 210, height: 210)

                Text(fish.displayName)
                    .font(PicoTypography.cardTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("rare")
                    .font(PicoTypography.largePill)
                    .foregroundStyle(FishRarity.rare.picoStyle.pillTextColor)
                    .padding(.horizontal, PicoSpacing.iconTextGap)
                    .padding(.vertical, 6)
                    .background(FishRarity.rare.picoStyle.pillBackgroundColor)
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(fish.accessibilityLabel))
    }
}

private struct OnboardingConfettiVisual: View {
    let reduceMotion: Bool
    @State private var startDate = Date()

    private let cycleDuration: TimeInterval = 3.2
    private let particles = OnboardingConfettiParticle.particles

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(startDate)
                let cycleElapsed = reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: cycleDuration)

                for particle in particles {
                    let progress = reduceMotion ? 0.34 : particle.progress(at: cycleElapsed)
                    guard progress > 0 || reduceMotion else { continue }

                    let easedProgress = 1 - pow(1 - progress, 2)
                    let x = size.width * particle.unitX + particle.drift * CGFloat(easedProgress)
                    let y = size.height * particle.startY + particle.fall * CGFloat(easedProgress)
                    let opacity = reduceMotion ? 0.72 : particle.opacity(at: progress)
                    guard opacity > 0 else { continue }

                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(particle.rotation(at: progress)))
                        layer.fill(
                            particle.path,
                            with: .color(particle.color.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear {
            startDate = Date()
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingConfettiParticle {
    enum Shape {
        case circle
        case roundedRect
    }

    let unitX: CGFloat
    let startY: CGFloat
    let drift: CGFloat
    let fall: CGFloat
    let delay: TimeInterval
    let duration: TimeInterval
    let size: CGSize
    let shape: Shape
    let color: Color
    let spin: Double

    var path: Path {
        let rect = CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )

        switch shape {
        case .circle:
            return Path(ellipseIn: rect)
        case .roundedRect:
            return Path(roundedRect: rect, cornerRadius: min(size.width, size.height) * 0.28)
        }
    }

    func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= delay else { return 0 }
        return min(1, max(0, (elapsed - delay) / duration))
    }

    func opacity(at progress: Double) -> Double {
        min(1, max(0, 1 - pow(progress, 2.4)))
    }

    func rotation(at progress: Double) -> Double {
        spin * progress
    }

    static let particles: [OnboardingConfettiParticle] = [
        .init(unitX: 0.16, startY: 0.18, drift: -8, fall: 58, delay: 0.00, duration: 1.55, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.warning, spin: 2.4),
        .init(unitX: 0.24, startY: 0.08, drift: 14, fall: 72, delay: 0.03, duration: 1.68, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.success, spin: -2.1),
        .init(unitX: 0.35, startY: 0.12, drift: -12, fall: 66, delay: 0.08, duration: 1.52, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.primary, spin: 1.7),
        .init(unitX: 0.63, startY: 0.10, drift: 10, fall: 74, delay: 0.02, duration: 1.62, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.error, spin: 2.9),
        .init(unitX: 0.74, startY: 0.16, drift: -11, fall: 56, delay: 0.11, duration: 1.46, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.warning, spin: -2.7),
        .init(unitX: 0.86, startY: 0.20, drift: 9, fall: 62, delay: 0.05, duration: 1.58, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.primary, spin: 2.2),
        .init(unitX: 0.20, startY: 0.42, drift: 18, fall: 42, delay: 0.18, duration: 1.38, size: CGSize(width: 4, height: 4), shape: .circle, color: PicoColors.success, spin: -1.5),
        .init(unitX: 0.44, startY: 0.30, drift: 15, fall: 54, delay: 0.21, duration: 1.36, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.warning, spin: -2.8),
        .init(unitX: 0.57, startY: 0.32, drift: -15, fall: 52, delay: 0.16, duration: 1.42, size: CGSize(width: 4, height: 7), shape: .roundedRect, color: PicoColors.error, spin: 2.5),
        .init(unitX: 0.82, startY: 0.38, drift: -18, fall: 44, delay: 0.22, duration: 1.32, size: CGSize(width: 4, height: 8), shape: .roundedRect, color: PicoColors.success, spin: 2.4),
        .init(unitX: 0.26, startY: 0.62, drift: -16, fall: 34, delay: 0.24, duration: 1.24, size: CGSize(width: 5, height: 5), shape: .circle, color: PicoColors.warning, spin: 1.8),
        .init(unitX: 0.62, startY: 0.58, drift: -10, fall: 38, delay: 0.27, duration: 1.22, size: CGSize(width: 5, height: 8), shape: .roundedRect, color: PicoColors.primary, spin: -2.5)
    ]
}

private struct OnboardingFishImage: View {
    let fish: OnboardingRareFreshwaterFish

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "fish.fill")
                    .font(PicoTypography.symbol(size: 120, weight: .semibold))
                    .foregroundStyle(FishRarity.rare.picoStyle.iconFallbackColor)
            }
        }
    }

    private var image: UIImage? {
        imageResourceCandidates
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }

    private var imageResourceCandidates: [String] {
        var candidates = [
            "Icons/fish/\(fish.assetName)",
            "Icons/fish/\(fish.assetName).png",
            "fish/\(fish.assetName)",
            "fish/\(fish.assetName).png",
            fish.assetName,
            "\(fish.assetName).png"
        ]

        if let flatAssetName = fish.assetName.split(separator: "/").last.map(String.init) {
            candidates.append("Icons/fish/\(flatAssetName)")
            candidates.append("Icons/fish/\(flatAssetName).png")
            candidates.append(flatAssetName)
            candidates.append("\(flatAssetName).png")
        }

        return candidates
    }
}

private struct OnboardingMovingIslandVisual: View {
    private var participant: IslandParticipant {
        IslandParticipant(
            profile: UserProfile(
                userID: UUID(uuidString: "4F2FBD45-57C9-4B16-8DE1-07B4460831D6") ?? UUID(),
                username: "pico",
                displayName: "Pico",
                avatarConfig: AvatarCatalog.defaultConfig
            ),
            bondLevel: 0
        )
    }

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: nil,
            participants: [participant],
            isFishingMode: false,
            usesHappyIdleAvatars: true,
            happyIdlePlacement: .center,
            mapStyle: .originalIsland,
            maxTileWidth: 50,
            mapYOffset: -76
        )
        .accessibilityLabel(Text("Pico avatar smiling on the island"))
    }
}

private struct OnboardingFriendsIslandVisual: View {
    private var participants: [IslandParticipant] {
        [
            IslandParticipant(
                profile: UserProfile(
                    userID: UUID(uuidString: "4F2FBD45-57C9-4B16-8DE1-07B4460831D6") ?? UUID(),
                    username: "pico",
                    displayName: "Pico",
                    avatarConfig: AvatarCatalog.defaultConfig
                ),
                bondLevel: 0
            ),
            IslandParticipant(
                profile: UserProfile(
                    userID: UUID(uuidString: "A0F2D726-1967-45FB-89E9-A21DD3C0C3E8") ?? UUID(),
                    username: "mika",
                    displayName: "Mika",
                    avatarConfig: AvatarCatalog.defaultConfig.withHat(.shark)
                ),
                bondLevel: 4
            ),
            IslandParticipant(
                profile: UserProfile(
                    userID: UUID(uuidString: "D3081671-73F5-47D4-88ED-4BC474648178") ?? UUID(),
                    username: "kai",
                    displayName: "Kai",
                    avatarConfig: AvatarCatalog.defaultConfig.withHat(.beanie)
                ),
                bondLevel: 3
            ),
            IslandParticipant(
                profile: UserProfile(
                    userID: UUID(uuidString: "93AF8B36-2CF3-4306-B4D9-EF498F45F00B") ?? UUID(),
                    username: "lena",
                    displayName: "Lena",
                    avatarConfig: AvatarCatalog.defaultConfig.withHat(.bow)
                ),
                bondLevel: 0
            )
        ]
    }

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: nil,
            participants: participants,
            isFishingMode: false,
            usesHappyIdleAvatars: true,
            happyIdlePlacement: .spreadOut,
            mapStyle: .originalIsland,
            maxTileWidth: 50,
            mapYOffset: -76
        )
        .accessibilityLabel(Text("Pico and three friends smiling on the island"))
    }
}

private struct OnboardingReelButton: View {
    @StateObject private var reelHaptics = ReelHaptics()
    @State private var isReeling = false
    @State private var reelProgress: CGFloat = 0

    let title: String
    let action: () -> Void

    private let reelFillDuration: TimeInterval = 0.8

    var body: some View {
        label
            .contentShape(Capsule(style: .continuous))
            .onLongPressGesture(
                minimumDuration: reelFillDuration,
                maximumDistance: 48,
                pressing: updateReelingState,
                perform: completeReel
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
            .onDisappear {
                stopReelingHaptics()
            }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Text("Hold down to pull")
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textOnPrimary.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: PicoSpacing.compact) {
                Text(isReeling ? "Reeling..." : title)
                    .font(PicoTypography.actionTitle)

                OnboardingFishingPoleIcon()
                    .frame(width: 25, height: 25)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(PicoColors.textOnPrimary)
        .padding(.horizontal, PicoSpacing.section)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(background)
        .clipShape(Capsule(style: .continuous))
    }

    private var background: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(hex: 0x54B8FF))

                Rectangle()
                    .fill(Color(hex: 0x2F9FEA))
                    .frame(width: proxy.size.width * reelProgress)
            }
            .clipShape(Capsule(style: .continuous))
        }
    }

    private func updateReelingState(_ isPressing: Bool) {
        isReeling = isPressing
        if isPressing {
            reelHaptics.start()
        } else {
            stopReelingHaptics()
        }

        withAnimation(isPressing ? .linear(duration: reelFillDuration) : .easeOut(duration: 0.22)) {
            reelProgress = isPressing ? 1 : 0
        }
    }

    private func completeReel() {
        action()
        stopReelingHaptics()

        withAnimation(.easeOut(duration: 0.18)) {
            reelProgress = 0
            isReeling = false
        }
    }

    private func stopReelingHaptics() {
        reelHaptics.stop()
    }
}

private struct StartFishingOnboardingVisual: View {
    let isFishing: Bool
    var showsAvatar = true

    private var previewProfile: UserProfile {
        UserProfile(
            userID: UUID(uuidString: "4F2FBD45-57C9-4B16-8DE1-07B4460831D6") ?? UUID(),
            username: "pico",
            displayName: "Pico",
            avatarConfig: AvatarCatalog.defaultConfig
        )
    }

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: showsAvatar ? previewProfile : nil,
            participants: showsAvatar ? nil : [],
            isFishingMode: isFishing,
            usesHappyIdleAvatars: showsAvatar && !isFishing,
            happyIdlePlacement: .center,
            mapStyle: .originalIsland,
            maxTileWidth: 50,
            mapYOffset: -76
        )
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        guard showsAvatar else { return "Pico island" }
        return isFishing ? "Pico avatar fishing on the island" : "Pico avatar on the island"
    }
}

private struct OnboardingProgressHeader: View {
    let currentIndex: Int
    let totalCount: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            Button(action: onBack) {
                PicoIcon(.chevronLeftRegular, size: 22)
                    .foregroundStyle(PicoColors.textPrimary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            OnboardingPageIndicator(
                currentIndex: currentIndex,
                totalCount: totalCount
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PicoSpacing.standard)
        .frame(height: 72)
        .background(PicoColors.appBackground)
    }
}

private struct OnboardingPrimaryCTALabel: View {
    let title: String
    var showsFishingPole = false

    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            Text(title)

            if showsFishingPole {
                OnboardingFishingPoleIcon()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct OnboardingWelcomeTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        VStack(spacing: PicoSpacing.compact) {
            Text(OnboardingStep.welcome.title)
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            Text(OnboardingStep.welcome.placeholderText)
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(OnboardingStep.welcome.title) \(OnboardingStep.welcome.placeholderText)"))
    }
}

private struct OnboardingRareFishTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text(OnboardingStep.rareFish.title)
        .font(titleFont)
        .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingStep.rareFish.title))
    }
}

private struct OnboardingRewardCelebrationTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text(OnboardingStep.rewardCelebration.title)
            .font(titleFont)
            .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingStep.rewardCelebration.title))
    }
}

private struct OnboardingAuthHandoffTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text(OnboardingStep.authHandoff.title)
            .font(titleFont)
            .foregroundStyle(PicoColors.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(OnboardingStep.authHandoff.title))
    }
}

private struct OnboardingFocusWithFriendsTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text(OnboardingStep.focusWithFriends.title)
            .font(titleFont)
            .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(Text(OnboardingStep.focusWithFriends.title))
    }
}

private struct OnboardingFishingPoleIcon: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: 22, weight: .semibold))
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/FishingPole_New",
            "Icons/FishingPole_New.png",
            "FishingPole_New",
            "FishingPole_New.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct OnboardingPageIndicator: View {
    let currentIndex: Int
    let totalCount: Int

    private var progress: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(totalCount)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(PicoColors.border)

                Capsule(style: .continuous)
                    .fill(PicoColors.primary)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Onboarding step \(currentIndex + 1) of \(totalCount)"))
    }
}
