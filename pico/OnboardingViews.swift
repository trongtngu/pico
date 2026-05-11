//
//  OnboardingViews.swift
//  pico
//
//  Created by Codex on 3/5/2026.
//

import SpriteKit
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
                    AuthEntryAvatarView()
                        .frame(width: 180, height: 180)

                    VStack(spacing: PicoSpacing.compact) {
                        PicoLogoImage()
                            .frame(width: 180, height: 80)

                        Text("Guilt-free focus")
                            .font(PicoTypography.body)
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

private struct AuthEntryAvatarView: View {
    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: AuthEntryAvatarScene(size: proxy.size),
                options: [.allowsTransparency]
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Happy Pico avatar wearing a green scarf"))
    }
}

private final class AuthEntryAvatarScene: SKScene {
    private static let idleActionKey = "auth-entry-idle"

    private var renderedSize: CGSize = .zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        redrawIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redrawIfNeeded()
    }

    private func redrawIfNeeded() {
        guard size.width > 0, size.height > 0, size != renderedSize else { return }

        renderedSize = size
        removeAllChildren()

        let frames = AvatarHappyIdleFrames(hat: .none, scarf: .green).layeredFrames
        let sprite = AvatarLayeredSpriteNode(frames: frames)
        let spriteSide = min(size.width, size.height)
        sprite.spriteSize = CGSize(width: spriteSide, height: spriteSide)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.runAnimation(
            with: frames,
            row: 0,
            timePerFrame: 0.10,
            key: Self.idleActionKey
        )
        addChild(sprite)
    }
}

struct OnboardingSequenceView: View {
    let onBackToEntry: () -> Void
    let onSignup: () -> Void
    let onLogin: () -> Void

    @State private var currentStep: OnboardingStep = OnboardingStep.ordered.first ?? .startFishing
    @State private var hasTrackedOnboardingStart = false
    @State private var lastTrackedScreenStep: OnboardingStep?
    @State private var selectedPhoneUsageHours = 4
    @State private var doesNotKnowPhoneUsage = false
    @State private var selectedFocusIntents: Set<OnboardingFocusIntent> = [.studying]
    @State private var selectedFocusGoal: OnboardingFocusGoal = .twentyFiveMinutes
    @State private var selectedFocusBarrier: OnboardingFocusBarrier?
    @State private var hasTriedProductivityApps: Bool?

    private let onboardingVariant = "default"

    private var currentIndex: Int {
        OnboardingStep.ordered.firstIndex(of: currentStep) ?? 0
    }

    private var primaryCTATitle: String {
        if currentStep.isPreferenceStep {
            return "Continue"
        }

        if currentStep == .startFishing {
            return "Continue"
        }

        if currentStep == .brokenLine {
            return "continue"
        }

        return "Continue"
    }

    private var primaryCTAAnalyticsActionName: String {
        switch currentStep {
        case .startFishing:
            "start_fishing"
        case .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience, .stayFocused, .brokenLine, .rareFish, .friendBonds, .authHandoff:
            "next"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = min(max(proxy.size.height * 0.42, 320), 430)

            VStack(spacing: 0) {
                OnboardingProgressHeader(
                    currentIndex: currentIndex,
                    totalCount: OnboardingStep.ordered.count,
                    onBack: goBack
                )

                VStack(spacing: 0) {
                    if currentStep.isPreferenceStep {
                        Spacer(minLength: PicoSpacing.compact)

                        OnboardingSetupStepContent(
                            step: currentStep,
                            selectedPhoneUsageHours: $selectedPhoneUsageHours,
                            doesNotKnowPhoneUsage: $doesNotKnowPhoneUsage,
                            selectedFocusIntents: $selectedFocusIntents,
                            selectedFocusGoal: $selectedFocusGoal,
                            selectedFocusBarrier: $selectedFocusBarrier,
                            hasTriedProductivityApps: $hasTriedProductivityApps
                        )

                        Spacer(minLength: PicoSpacing.compact)

                        if currentStep == .phoneUsage {
                            OnboardingChoiceButton(
                                title: "I don't know",
                                isSelected: doesNotKnowPhoneUsage
                            ) {
                                doesNotKnowPhoneUsage.toggle()
                            }
                            .padding(.bottom, PicoSpacing.iconTextGap)
                        }

                        Button(action: handlePrimaryAction) {
                            OnboardingPrimaryCTALabel(title: primaryCTATitle)
                        }
                        .buttonStyle(PicoPrimaryButtonStyle())
                    } else {
                        Spacer(minLength: PicoSpacing.compact)

                        VStack(spacing: 0) {
                            OnboardingStoryStepTitle(currentStep: currentStep)

                            Group {
                                if currentStep == .startFishing || currentStep == .stayFocused || currentStep == .brokenLine {
                                    StartFishingOnboardingVisual(
                                        isFishing: currentStep != .startFishing,
                                        showsFriend: currentStep == .brokenLine
                                    )
                                        .frame(height: visualHeight)
                                } else if currentStep == .rareFish {
                                    RareSeaCreaturesOnboardingVisual()
                                        .frame(height: visualHeight)
                                } else if currentStep == .friendBonds {
                                    FriendBondsOnboardingVisual()
                                        .frame(height: visualHeight)
                                } else if currentStep == .authHandoff {
                                    OnboardingAccountAvatarVisual()
                                        .frame(height: visualHeight)
                                } else {
                                    OnboardingPlaceholderVisual(
                                        symbol: currentStep.visualSymbol,
                                        subtitle: "Placeholder visual"
                                    )
                                    .frame(width: min(visualHeight, 300), height: min(visualHeight, 300))
                                }
                            }
                        }

                        Spacer(minLength: PicoSpacing.compact)

                        OnboardingStoryStepActions(
                            currentStep: currentStep,
                            primaryCTATitle: primaryCTATitle,
                            handlePrimaryAction: handlePrimaryAction,
                            handleSignupAction: handleSignupAction,
                            onLogin: onLogin
                        )
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            trackOnboardingStartIfNeeded()
            trackCurrentScreenIfNeeded()
        }
        .onChange(of: currentStep) {
            trackCurrentScreenIfNeeded()
        }
    }

    private func handlePrimaryAction() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: primaryCTAAnalyticsActionName,
            onboardingVariant: onboardingVariant
        ))
        goForward()
    }

    private func handleSignupAction() {
        AnalyticsService.track(.onboardingActionTapped(
            screenName: currentStep.analyticsName,
            actionName: "create_account",
            onboardingVariant: onboardingVariant
        ))
        onSignup()
    }

    private func goForward() {
        let steps = OnboardingStep.ordered
        guard currentIndex < steps.index(before: steps.endIndex) else {
            onSignup()
            return
        }

        currentStep = steps[currentIndex + 1]
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
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case phoneUsage
    case focusIntent
    case focusGoal
    case focusBarrier
    case productivityExperience
    case startFishing
    case stayFocused
    case brokenLine
    case rareFish
    case friendBonds
    case authHandoff

    static let ordered: [OnboardingStep] = [
        .phoneUsage,
        .focusIntent,
        .focusGoal,
        .productivityExperience,
        .focusBarrier,
        .startFishing,
        .stayFocused,
        .brokenLine,
        .authHandoff
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .startFishing:
            "Start fishing"
        case .stayFocused:
            "Catch fish while you focus"
        case .brokenLine:
            "Focus better with friends"
        case .rareFish:
            "Discover rare sea creatures"
        case .friendBonds:
            "Create strong bonds with friends"
        case .authHandoff:
            "Create an account"
        }
    }

    var placeholderText: String {
        switch self {
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
        case .startFishing:
            "Pico creates a guilt-free focus island"
        case .stayFocused:
            "Catch fish while you focus"
        case .brokenLine:
            "Placeholder copy for explaining that using your phone breaks the fishing line for that focus session."
        case .rareFish:
            ""
        case .friendBonds:
            ""
        case .authHandoff:
            ""
        }
    }

    var visualSymbol: String {
        switch self {
        case .phoneUsage:
            "1"
        case .focusIntent:
            "2"
        case .focusGoal:
            "3"
        case .productivityExperience:
            "4"
        case .focusBarrier:
            "5"
        case .startFishing:
            "6"
        case .stayFocused:
            "7"
        case .brokenLine:
            "8"
        case .rareFish:
            "9"
        case .friendBonds:
            "10"
        case .authHandoff:
            "11"
        }
    }

    var analyticsName: String {
        switch self {
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
        case .startFishing:
            "start_fishing"
        case .stayFocused:
            "stay_focused"
        case .brokenLine:
            "broken_line"
        case .rareFish:
            "rare_fish"
        case .friendBonds:
            "friend_bonds"
        case .authHandoff:
            "auth_handoff"
        }
    }

    var isPreferenceStep: Bool {
        switch self {
        case .phoneUsage, .focusIntent, .focusGoal, .focusBarrier, .productivityExperience:
            true
        case .startFishing, .stayFocused, .brokenLine, .rareFish, .friendBonds, .authHandoff:
            false
        }
    }
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
    @Binding var doesNotKnowPhoneUsage: Bool
    @Binding var selectedFocusIntents: Set<OnboardingFocusIntent>
    @Binding var selectedFocusGoal: OnboardingFocusGoal
    @Binding var selectedFocusBarrier: OnboardingFocusBarrier?
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
            case .startFishing, .stayFocused, .brokenLine, .rareFish, .friendBonds, .authHandoff:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var phoneUsageContent: some View {
        VStack(spacing: PicoSpacing.section) {
            OnboardingQuestionTitle(title: step.title)

            OnboardingPhoneUsageSlider(
                selectedHours: $selectedPhoneUsageHours,
                doesNotKnowPhoneUsage: $doesNotKnowPhoneUsage
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
                        isSelected: selectedFocusBarrier == barrier
                    ) {
                        selectedFocusBarrier = barrier
                    }
                }
            }
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
            if currentStep != .startFishing && currentStep != .stayFocused {
                if currentStep == .brokenLine {
                    OnboardingBrokenLineTitle()
                } else if currentStep == .rareFish {
                    OnboardingRareSeaCreaturesTitle()
                } else if currentStep == .friendBonds {
                    OnboardingFriendBondsTitle()
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

            if currentStep == .startFishing {
                OnboardingStartFishingTitle()
            } else if currentStep == .stayFocused {
                OnboardingStayFocusedTitle()
            } else if currentStep != .brokenLine && currentStep != .rareFish && currentStep != .friendBonds && currentStep != .authHandoff {
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
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: PicoSpacing.iconTextGap) {
            if currentStep == .authHandoff {
                VStack(spacing: PicoSpacing.iconTextGap) {
                    Button("Continue with email", action: handleSignupAction)
                        .buttonStyle(PicoPrimaryButtonStyle())

                    Button("Already have an account? Log in", action: onLogin)
                        .buttonStyle(PicoSecondaryButtonStyle())
                }
            } else {
                Button(action: handlePrimaryAction) {
                    OnboardingPrimaryCTALabel(title: primaryCTATitle)
                }
                .buttonStyle(PicoPrimaryButtonStyle())
            }
        }
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
    @Binding var doesNotKnowPhoneUsage: Bool

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
        doesNotKnowPhoneUsage = false
    }

    private func moveSelection(by offset: Int) {
        selectedHours = min(max(selectedHours + offset, hourRange.lowerBound), hourRange.upperBound)
        doesNotKnowPhoneUsage = false
    }
}

private struct StartFishingOnboardingVisual: View {
    let isFishing: Bool
    var showsFriend = false

    private var previewProfile: UserProfile {
        UserProfile(
            userID: UUID(uuidString: "4F2FBD45-57C9-4B16-8DE1-07B4460831D6") ?? UUID(),
            username: "pico",
            displayName: "Pico",
            avatarConfig: AvatarCatalog.defaultConfig
        )
    }

    private var friendProfile: UserProfile {
        UserProfile(
            userID: UUID(uuidString: "A0F2D726-1967-45FB-89E9-A21DD3C0C3E8") ?? UUID(),
            username: "kai",
            displayName: "Kai",
            avatarConfig: AvatarCatalog.defaultConfig.withHat(.beanie)
        )
    }

    private var participants: [IslandParticipant]? {
        guard showsFriend else { return nil }

        return [
            IslandParticipant(profile: previewProfile, bondLevel: 0),
            IslandParticipant(profile: friendProfile, bondLevel: 0)
        ]
    }

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: previewProfile,
            participants: participants,
            isFishingMode: isFishing,
            mapStyle: .originalIsland,
            maxTileWidth: 50,
            mapYOffset: -76
        )
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        if showsFriend {
            return "Pico and a friend avatar fishing together on the island"
        }

        return isFishing ? "Pico avatar fishing on the island" : "Pico avatar on the island"
    }
}

private struct RareSeaCreaturesOnboardingVisual: View {
    private let assetNames = [
        "Fish_MarlinSwordfish",
        "Fish_GreatWhiteShark",
        "Fish_HammerHeadShark",
        "Fish_Sunfish",
        "Fish_Tuna",
        "Fish_PufferFish",
        "TropicalFish_LionFish",
        "TropicalFish_ButterflyFish",
        "SeaInvertebrate_Octopus_Orange",
        "SeaMammal_Dolphin",
        "Fish_Salmon",
        "SeaShellfish_Lobster_Red"
    ]

    private let secondsPerStep: TimeInterval = 1.85
    private let visibleSlotCount = 5

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let trackWidth = min(proxy.size.width, 420)
                let itemSize = min(trackWidth * 0.68, min(proxy.size.height * 0.58, 260))
                let spacing = itemSize * 1.16
                let progress = context.date.timeIntervalSinceReferenceDate / secondsPerStep
                let step = floor(progress)
                let offset = CGFloat(progress - step) * spacing
                let firstIndex = Int(step)

                ZStack {
                    ForEach(0..<visibleSlotCount, id: \.self) { slot in
                        let assetName = assetNames[wrappedIndex(firstIndex + slot - 1)]
                        let xPosition = trackWidth / 2 + CGFloat(slot - 1) * spacing - offset

                        OnboardingFishSilhouette(assetName: assetName)
                            .frame(width: itemSize, height: itemSize)
                            .position(x: xPosition, y: itemSize / 2)
                    }
                }
                .frame(width: trackWidth, height: itemSize)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rare sea creature silhouettes moving from right to left"))
    }

    private func wrappedIndex(_ index: Int) -> Int {
        let remainder = index % assetNames.count
        return remainder >= 0 ? remainder : remainder + assetNames.count
    }
}

private struct FriendBondsOnboardingVisual: View {
    var body: some View {
        GeometryReader { proxy in
            let avatarSize = min(proxy.size.width * 0.64, min(proxy.size.height * 0.70, 270))
            let overlap = avatarSize * -0.42

            HStack(spacing: overlap) {
                OnboardingFriendAvatarView(facesLeft: false)
                    .frame(width: avatarSize, height: avatarSize)

                OnboardingFriendAvatarView(facesLeft: true)
                    .frame(width: avatarSize, height: avatarSize)
            }
            .frame(width: proxy.size.width, height: avatarSize)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Two happy Pico avatars wearing green scarves"))
    }
}

private struct OnboardingAccountAvatarVisual: View {
    var body: some View {
        GeometryReader { proxy in
            let avatarSize = min(proxy.size.width * 0.64, min(proxy.size.height * 0.64, 250))

            AuthEntryAvatarView()
                .frame(width: avatarSize, height: avatarSize)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Smiling Pico avatar wearing a green scarf"))
    }
}

private struct OnboardingFriendAvatarView: View {
    let facesLeft: Bool

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: OnboardingFriendAvatarScene(
                    size: proxy.size,
                    facesLeft: facesLeft
                ),
                options: [.allowsTransparency]
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
    }
}

private final class OnboardingFriendAvatarScene: SKScene {
    private static let idleActionKey = "friend-bonds-idle"

    private let facesLeft: Bool
    private var renderedSize: CGSize = .zero

    init(size: CGSize, facesLeft: Bool) {
        self.facesLeft = facesLeft
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.isOpaque = false
        view.backgroundColor = .clear
        redrawIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        redrawIfNeeded()
    }

    private func redrawIfNeeded() {
        guard size.width > 0, size.height > 0, size != renderedSize else { return }

        renderedSize = size
        removeAllChildren()

        let frames = AvatarHappyIdleFrames(hat: .none, scarf: .green).layeredFrames
        let sprite = AvatarLayeredSpriteNode(frames: frames)
        let spriteSide = min(size.width, size.height)
        sprite.spriteSize = CGSize(width: spriteSide, height: spriteSide)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.xScale = facesLeft ? -abs(sprite.xScale) : abs(sprite.xScale)
        sprite.runAnimation(
            with: frames,
            row: 0,
            timePerFrame: 0.10,
            key: Self.idleActionKey
        )
        addChild(sprite)
    }
}

private struct OnboardingFishSilhouette: View {
    let assetName: String

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .foregroundStyle(Color.black)
            } else {
                Image(systemName: "fish")
                    .font(PicoTypography.symbol(size: 120, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/fish/\(assetName)",
            "Icons/fish/\(assetName).png",
            "fish/\(assetName)",
            "fish/\(assetName).png",
            assetName,
            "\(assetName).png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
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
        .frame(height: 56)
        .background(PicoColors.appBackground)
    }
}

private struct OnboardingPrimaryCTALabel: View {
    let title: String

    var body: some View {
        Text(title)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct OnboardingStartFishingTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        VStack(spacing: PicoSpacing.tiny) {
            Text("Welcome to Pico!")
            Text("Your guilt-free focus island")
        }
        .font(titleFont)
        .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Welcome! to pico. Stay at a guilt-free focus island"))
    }
}

private struct OnboardingFirstCatchTitle: View {
    let titleFont: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PicoSpacing.tiny) {
            fishingPoleIcon
                .hidden()
                .accessibilityHidden(true)

            Text("What will you catch today?")
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            fishingPoleIcon
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var fishingPoleIcon: some View {
        OnboardingFishingPoleIcon()
            .frame(width: 24, height: 24)
            .alignmentGuide(.firstTextBaseline) { context in
                context[VerticalAlignment.center] + 7
            }
    }
}

private struct OnboardingStayFocusedTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text("Catch fish while you focus")
            .font(titleFont)
            .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Catch fish while you focus"))
    }
}

private struct OnboardingFriendBondsTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        VStack(spacing: 2) {
            Text("Focus with friends and")
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            HStack(alignment: .center, spacing: PicoSpacing.tiny) {
                Text("create strong bonds")
                    .font(titleFont)
                    .foregroundStyle(PicoColors.textPrimary)

                OnboardingGreenScarfImage()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Focus with friends and create strong bonds"))
    }
}

private struct OnboardingRareSeaCreaturesTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        HStack(alignment: .center, spacing: PicoSpacing.tiny) {
            Text(OnboardingStep.rareFish.title)
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            OnboardingAnchorImage()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(OnboardingStep.rareFish.title))
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

private struct OnboardingAnchorImage: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/Anchor",
            "Icons/Anchor.png",
            "Anchor",
            "Anchor.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct OnboardingGreenScarfImage: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/green_scarf",
            "Icons/green_scarf.png",
            "Icons/Scarf_Green",
            "Icons/Scarf_Green.png",
            "green_scarf",
            "green_scarf.png",
            "Scarf_Green",
            "Scarf_Green.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct OnboardingBucketImage: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/Bucket",
            "Icons/Bucket.png",
            "Icons/bucket",
            "Icons/bucket.png",
            "Bucket",
            "Bucket.png",
            "bucket",
            "bucket.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct OnboardingBrokenLineTitle: View {
    private let titleFont = PicoTypography.sectionTitle

    var body: some View {
        Text(OnboardingStep.brokenLine.title)
            .font(titleFont)
            .foregroundStyle(PicoColors.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(Text(OnboardingStep.brokenLine.title))
    }
}

private struct OnboardingEmptyBucketImage: View {
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private var image: UIImage? {
        [
            "Icons/Empty_Bucket",
            "Icons/Empty_Bucket.png",
            "Icons/empty_bucket",
            "Icons/empty_bucket.png",
            "Empty_Bucket",
            "Empty_Bucket.png",
            "empty_bucket",
            "empty_bucket.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
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

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? PicoColors.primary : PicoColors.border)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Onboarding step \(currentIndex + 1) of \(totalCount)"))
    }
}

private struct OnboardingPlaceholderVisual: View {
    let symbol: String
    let subtitle: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PicoRadius.large, style: .continuous)
                .fill(PicoColors.softSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: PicoRadius.large, style: .continuous)
                        .stroke(PicoColors.border, lineWidth: 1)
                )

            VStack(spacing: PicoSpacing.compact) {
                Text(symbol)
                    .font(PicoTypography.largeValue)
                    .foregroundStyle(PicoColors.primary)

                Text(subtitle)
                    .font(PicoTypography.captionSemibold)
                    .foregroundStyle(PicoColors.textSecondary)
            }
        }
    }
}
