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

    private var primaryCTATitle: String {
        if currentStep == .startFishing {
            return "Start fishing"
        }

        if currentStep == .brokenLine {
            return "I'll focus"
        }

        return "Continue"
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = min(max(proxy.size.height * 0.48, 390), 460)

            VStack(spacing: 0) {
                OnboardingProgressHeader(
                    currentIndex: currentIndex,
                    totalCount: OnboardingStep.ordered.count,
                    onBack: goBack,
                    topInset: proxy.safeAreaInsets.top
                )

                VStack(spacing: 0) {
                    Group {
                        if currentStep == .startFishing || currentStep == .stayFocused || currentStep == .brokenLine {
                            StartFishingOnboardingVisual(isFishing: currentStep != .startFishing)
                                .frame(height: visualHeight)
                        } else if currentStep == .rareFish {
                            RareSeaCreaturesOnboardingVisual()
                                .frame(height: visualHeight)
                        } else if currentStep == .friendBonds {
                            FriendBondsOnboardingVisual()
                                .frame(height: visualHeight)
                        } else {
                            OnboardingPlaceholderVisual(
                                symbol: currentStep.visualSymbol,
                                subtitle: "Placeholder visual"
                            )
                            .frame(width: min(visualHeight, 300), height: min(visualHeight, 300))
                        }
                    }
                    .padding(.top, PicoSpacing.section)

                    Spacer(minLength: PicoSpacing.compact)

                    VStack(spacing: PicoSpacing.section) {
                        VStack(spacing: PicoSpacing.compact) {
                            if currentStep != .startFishing && currentStep != .stayFocused {
                                if currentStep == .brokenLine {
                                    OnboardingBrokenLineTitle()
                                } else if currentStep == .rareFish {
                                    OnboardingRareSeaCreaturesTitle()
                                } else if currentStep == .friendBonds {
                                    OnboardingFriendBondsTitle()
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
                            } else if currentStep != .brokenLine && currentStep != .rareFish && currentStep != .friendBonds {
                                Text(currentStep.placeholderText)
                                    .font(PicoTypography.body)
                                    .foregroundStyle(PicoColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if currentStep == .authHandoff {
                            VStack(spacing: PicoSpacing.iconTextGap) {
                                Button("Create account", action: onSignup)
                                    .buttonStyle(PicoPrimaryButtonStyle())

                                Button("Log in", action: onLogin)
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
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func handlePrimaryAction() {
        goForward()
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
            "Discover sea creatures as you focus"
        case .brokenLine:
            "Using your phone will scare away the sea life"
        case .rareFish:
            "Discover rare sea creatures"
        case .friendBonds:
            "Create strong bonds with friends"
        case .authHandoff:
            "Signup/login"
        }
    }

    var placeholderText: String {
        switch self {
        case .startFishing:
            "Welcome to Pico! Discover sea creatures as you focus"
        case .stayFocused:
            "Discover sea creatures as you focus."
        case .brokenLine:
            "Placeholder copy for explaining that using your phone breaks the fishing line for that focus session."
        case .rareFish:
            ""
        case .friendBonds:
            ""
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

private struct StartFishingOnboardingVisual: View {
    let isFishing: Bool

    private static let previewProfile = UserProfile(
        userID: UUID(uuidString: "4F2FBD45-57C9-4B16-8DE1-07B4460831D6") ?? UUID(),
        username: "pico",
        displayName: "Pico",
        avatarConfig: AvatarCatalog.defaultConfig
    )

    var body: some View {
        VillageView(
            residents: [],
            currentUserProfile: Self.previewProfile,
            isFishingMode: isFishing,
            mapStyle: .originalIsland,
            maxTileWidth: 50,
            mapYOffset: -76
        )
        .accessibilityLabel(Text(isFishing ? "Pico avatar fishing on the island" : "Pico avatar on the island"))
    }
}

private struct RareSeaCreaturesOnboardingVisual: View {
    private let assetNames = [
        "Fish_WhaleShark",
        "SeaMammal_Narwhale",
        "Fish_HammerHeadShark",
        "SeaInvertebrate_Jellyfish_Blue",
        "DeepSeaFish_AnglerFish",
        "SeaReptile_Turtle",
        "SeaMammal_Orca",
        "SeaShellfish_Nautilus",
        "Fish_StingRay",
        "SeaInvertebrate_Octopus_Orange",
        "Fish_GreatWhiteShark",
        "SeaInvertebrate_Squid_Pink"
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
    let topInset: CGFloat

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
        .padding(.top, max(0, topInset))
        .frame(height: topInset + 56, alignment: .top)
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
    private let titleFont = PicoTypography.primary(size: 24, weight: .semibold)

    var body: some View {
        VStack(spacing: 2) {
            Text("Welcome to Pico!")
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            OnboardingFirstCatchTitle(titleFont: titleFont)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Welcome to Pico! What will you catch today?"))
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
    private let titleFont = PicoTypography.primary(size: 24, weight: .semibold)

    var body: some View {
        VStack(spacing: 2) {
            Text("Discover sea creatures")
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            HStack(alignment: .center, spacing: PicoSpacing.tiny) {
                Text("as you focus.")
                    .font(titleFont)
                    .foregroundStyle(PicoColors.textPrimary)

                OnboardingLanternImage()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Discover sea creatures as you focus."))
    }
}

private struct OnboardingFriendBondsTitle: View {
    private let titleFont = PicoTypography.primary(size: 24, weight: .semibold)

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
    private let titleFont = PicoTypography.primary(size: 24, weight: .semibold)

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

private struct OnboardingLanternImage: View {
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
            "Icons/Lantern_On",
            "Icons/Lantern_On.png",
            "Icons/lantern_on",
            "Icons/lantern_on.png",
            "Lantern_On",
            "Lantern_On.png",
            "lantern_on",
            "lantern_on.png"
        ]
            .lazy
            .compactMap { UIImage(named: $0) }
            .first
    }
}

private struct OnboardingBrokenLineTitle: View {
    private let titleFont = PicoTypography.primary(size: 24, weight: .semibold)

    var body: some View {
        VStack(spacing: 2) {
            Text("Using your phone scares")
                .font(titleFont)
                .foregroundStyle(PicoColors.textPrimary)

            HStack(alignment: .center, spacing: PicoSpacing.tiny) {
                Text("away the sea life")
                    .font(titleFont)
                    .foregroundStyle(PicoColors.textPrimary)

                OnboardingEmptyBucketImage()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
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
