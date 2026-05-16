//
//  PicoPlusPaywallView.swift
//  pico
//
//  Created by Codex on 16/5/2026.
//

import SwiftUI

enum PicoPlusCTAButtonSize {
    case regular
    case pill
}

struct PicoPlusCTAButton: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var picoPlusStore: PicoPlusStore

    let title: String
    let isLoading: Bool
    let size: PicoPlusCTAButtonSize
    private let source: PicoPlusPaywallSource
    private let beforePresentation: (@MainActor () async -> Void)?
    private let afterPresentation: (@MainActor () -> Void)?
    @State private var isHovering = false

    init(
        title: String = "Unlock with Plus",
        isLoading: Bool = false,
        size: PicoPlusCTAButtonSize = .regular,
        source: PicoPlusPaywallSource,
        beforePresentation: (@MainActor () async -> Void)? = nil,
        afterPresentation: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.isLoading = isLoading
        self.size = size
        self.source = source
        self.beforePresentation = beforePresentation
        self.afterPresentation = afterPresentation
    }

    var body: some View {
        Button {
            presentPaywall()
        } label: {
            HStack(spacing: size.iconTextSpacing) {
                PicoIcon(.lockClosed, size: size.iconSize)
                    .accessibilityHidden(true)

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
        .buttonStyle(PicoPlusCTAButtonStyle(size: size, isHovering: isHovering))
        .disabled(isLoading)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
    }

    private func presentPaywall() {
        guard !isLoading else { return }

        Task { @MainActor in
            await beforePresentation?()
            await picoPlusStore.presentPaywall(
                source: source,
                authSession: sessionStore.session
            )
            afterPresentation?()
        }
    }
}

private extension PicoPlusCTAButtonSize {
    var iconTextSpacing: CGFloat {
        switch self {
        case .regular:
            8
        case .pill:
            5
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .regular:
            15
        case .pill:
            11
        }
    }
}

struct PicoPlusCTAButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let size: PicoPlusCTAButtonSize
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let isRaised = isHovering && !isPressed && isEnabled

        configuration.label
            .font(font)
            .tracking(size == .regular ? 0.16 : 0)
            .foregroundStyle(.white)
            .frame(maxWidth: maxWidth, minHeight: minHeight, maxHeight: minHeight)
            .padding(.horizontal, horizontalPadding)
            .background(background)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(isPressed ? 0.38 : 0.45), lineWidth: 1)
            )
            .brightness(isPressed ? -0.02 : (isRaised ? 0.04 : 0))
            .scaleEffect(isPressed ? 0.99 : 1)
            .offset(y: isPressed ? 1 : (isRaised ? -1 : 0))
            .opacity(isEnabled ? 1 : 0.62)
            .animation(.easeInOut(duration: 0.16), value: isPressed)
            .animation(.easeInOut(duration: 0.16), value: isHovering)
            .contentShape(Capsule(style: .continuous))
    }

    private var font: Font {
        switch size {
        case .regular:
            PicoTypography.primary(size: 16, weight: .heavy)
        case .pill:
            PicoTypography.statusLabel
        }
    }

    private var maxWidth: CGFloat? {
        switch size {
        case .regular:
            .infinity
        case .pill:
            nil
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .regular:
            56
        case .pill:
            30
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular:
            PicoSpacing.standard
        case .pill:
            11
        }
    }

    private var background: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x7BAE3B), location: 0),
                            .init(color: Color(hex: 0xA9BF34), location: 0.42),
                            .init(color: Color(hex: 0xE4A72F), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.28), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.38),
                            .init(color: .white.opacity(0), location: 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
