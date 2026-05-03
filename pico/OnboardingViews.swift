//
//  OnboardingViews.swift
//  pico
//
//  Created by Codex on 3/5/2026.
//

import SwiftUI

struct AuthEntryView: View {
    let onGetStarted: () -> Void
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: PicoSpacing.largeSection) {
                    Spacer(minLength: max(28, proxy.safeAreaInsets.top + 20))

                    VStack(spacing: PicoSpacing.section) {
                        OnboardingPlaceholderVisual(symbol: "P", subtitle: "Pico")
                            .frame(width: 180, height: 180)

                        VStack(spacing: PicoSpacing.compact) {
                            Text("Pico")
                                .font(PicoTypography.screenTitle)
                                .foregroundStyle(PicoColors.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Focus together and collect sea creatures along the way.")
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
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

struct OnboardingSequenceView: View {
    let onBackToEntry: () -> Void
    let onSignup: () -> Void
    let onLogin: () -> Void

    @State private var currentStep: OnboardingStep = OnboardingStep.ordered.first ?? .startFishing

    private var currentIndex: Int {
        OnboardingStep.ordered.firstIndex(of: currentStep) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                OnboardingTopBar(
                    canGoBack: currentIndex > 0,
                    onBack: goBack,
                    onClose: onBackToEntry
                )
                .padding(.top, max(0, proxy.safeAreaInsets.top))

                VStack(spacing: PicoSpacing.section) {
                    OnboardingPageIndicator(
                        currentIndex: currentIndex,
                        totalCount: OnboardingStep.ordered.count
                    )

                    Spacer(minLength: PicoSpacing.compact)

                    OnboardingPlaceholderVisual(
                        symbol: currentStep.visualSymbol,
                        subtitle: "Placeholder visual"
                    )
                    .frame(width: 220, height: 220)

                    VStack(spacing: PicoSpacing.compact) {
                        Text(currentStep.title)
                            .font(PicoTypography.sectionTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(currentStep.placeholderText)
                            .font(PicoTypography.body)
                            .foregroundStyle(PicoColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: PicoSpacing.section)

                    if currentStep == .authHandoff {
                        VStack(spacing: PicoSpacing.iconTextGap) {
                            Button("Create account", action: onSignup)
                                .buttonStyle(PicoPrimaryButtonStyle())

                            Button("Log in", action: onLogin)
                                .buttonStyle(PicoSecondaryButtonStyle())
                        }
                    } else {
                        Button("Continue", action: goForward)
                            .buttonStyle(PicoPrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.top, PicoSpacing.standard)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
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
        guard currentIndex > 0 else {
            onBackToEntry()
            return
        }

        currentStep = OnboardingStep.ordered[currentIndex - 1]
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case startFishing
    case stayFocused
    case brokenLine
    case rareFish
    case friendBonds
    case authHandoff

    static let ordered: [OnboardingStep] = [
        .startFishing,
        .stayFocused,
        .brokenLine,
        .rareFish,
        .friendBonds,
        .authHandoff
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startFishing:
            "Start fishing"
        case .stayFocused:
            "Stay focused and add more sea creatures to your collection"
        case .brokenLine:
            "Using your phone breaks the fishing line"
        case .rareFish:
            "Discover rare fish"
        case .friendBonds:
            "Create strong bonds with friends"
        case .authHandoff:
            "Signup/login"
        }
    }

    var placeholderText: String {
        switch self {
        case .startFishing:
            "Placeholder copy for introducing focus sessions as fishing."
        case .stayFocused:
            "Placeholder copy for adding more sea creatures to your collection while you stay focused."
        case .brokenLine:
            "Placeholder copy for explaining that using your phone breaks the fishing line for that focus session."
        case .rareFish:
            "Placeholder copy for rare fish discovery."
        case .friendBonds:
            "Placeholder copy for friend bonds increasing rare creature encounters."
        case .authHandoff:
            "Placeholder copy for creating an account or logging in before entering Pico."
        }
    }

    var visualSymbol: String {
        switch self {
        case .startFishing:
            "1"
        case .stayFocused:
            "2"
        case .brokenLine:
            "3"
        case .rareFish:
            "4"
        case .friendBonds:
            "5"
        case .authHandoff:
            "6"
        }
    }
}

private struct OnboardingTopBar: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                PicoIcon(.chevronLeftRegular, size: 22)
                    .foregroundStyle(canGoBack ? PicoColors.textPrimary : PicoColors.textMuted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel(Text("Back"))

            Spacer(minLength: 0)

            Button(action: onClose) {
                PicoIcon(.xMarkRegular, size: 20)
                    .foregroundStyle(PicoColors.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close onboarding"))
        }
        .padding(.horizontal, PicoSpacing.compact)
        .frame(height: 48)
        .background(PicoColors.appBackground)
    }
}

private struct OnboardingPageIndicator: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? PicoColors.primary : PicoColors.border)
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
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
