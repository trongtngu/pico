//
//  PicoDesignSystem.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PicoColors {
    static let primary = Color(hex: 0x7BAE3B)
    static let secondaryAccent = Color(hex: 0x7C5CFF)
    static let streakAccent = Color(hex: 0xFF8A3D)

    static let appBackground = Color(hex: 0xFAF8F2)
    static let surface = Color(hex: 0xFFFFFF)
    static let softSurface = Color(hex: 0xF1EDE4)
    static let border = Color(hex: 0xE6E0D4)

    static let textPrimary = Color(hex: 0x171717)
    static let textSecondary = Color(hex: 0x737373)
    static let textMuted = Color(hex: 0xA3A3A3)
    static let textOnPrimary = Color(hex: 0xFFFFFF)

    static let success = Color(hex: 0x5FAE5D)
    static let warning = Color(hex: 0xF6A23A)
    static let error = Color(hex: 0xE85D5D)
    static let info = Color(hex: 0x5B8DEF)
    static let destructiveBackground = Color(hex: 0xFDECEC)
}

enum PicoSpacing {
    static let tiny: CGFloat = 4
    static let compact: CGFloat = 8
    static let iconTextGap: CGFloat = 12
    static let standard: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let section: CGFloat = 24
    static let largeSection: CGFloat = 32
    static let hero: CGFloat = 48
}

enum PicoRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 18
    static let large: CGFloat = 24
    static let modal: CGFloat = 28
    static let extraLarge: CGFloat = 32
    static let pill: CGFloat = 999
}

enum PicoTypography {
    static let screenTitle = Font.system(size: 42, weight: .bold, design: .rounded)
    static let sectionTitle = Font.system(size: 26, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(size: 21, weight: .bold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 14, weight: .medium, design: .rounded)
    static let tabLabel = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let button = Font.system(size: 17, weight: .bold, design: .rounded)
}

enum PicoShadow {
    static let tabBarColor = Color.black.opacity(0.09)
    static let tabBarRadius: CGFloat = 28
    static let tabBarY: CGFloat = 10

    static let raisedCardColor = Color.black.opacity(0.08)
    static let raisedCardRadius: CGFloat = 22
    static let raisedCardX: CGFloat = 0
    static let raisedCardY: CGFloat = 10
}

enum PicoTabStyle {
    static let activeForeground = PicoColors.primary
    static let inactiveForeground = PicoColors.textPrimary
    static let activePillBackground = PicoColors.softSurface
    static let barBackground = PicoColors.surface
    static let barBorder = PicoColors.border
}

enum PicoCreamCardStyle {
    static let background = PicoColors.appBackground
    static let border = PicoColors.border
    static let controlBackground = PicoColors.softSurface
    static let badgeBackground = PicoColors.appBackground
    static let divider = PicoColors.border.opacity(0.8)
    static let cornerRadius = PicoRadius.medium
    static let sheetCornerRadius = PicoRadius.modal
    static let borderWidth: CGFloat = 1
    static let contentPadding = PicoSpacing.cardPadding
    static let sheetCardPadding = PicoSpacing.standard
}

#if canImport(UIKit)
enum PicoUIColors {
    static let appBackground = UIColor(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF2 / 255, alpha: 1)
    static let softSurface = UIColor(red: 0xF1 / 255, green: 0xED / 255, blue: 0xE4 / 255, alpha: 1)
    static let textPrimary = UIColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, alpha: 1)
}

enum PicoSegmentedControlAppearance {
    static func configure() {
        let segmentedControl = UISegmentedControl.appearance()
        segmentedControl.backgroundColor = PicoUIColors.softSurface
        segmentedControl.selectedSegmentTintColor = PicoUIColors.appBackground
        segmentedControl.setTitleTextAttributes(
            [.foregroundColor: PicoUIColors.textPrimary],
            for: .normal
        )
        segmentedControl.setTitleTextAttributes(
            [.foregroundColor: PicoUIColors.textPrimary],
            for: .selected
        )
    }
}
#endif

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct PicoCreamCardModifier: ViewModifier {
    var cornerRadius: CGFloat = PicoCreamCardStyle.cornerRadius
    var showsShadow: Bool = true
    var padding: CGFloat? = nil
    var background: Color = PicoCreamCardStyle.background
    var border: Color = PicoCreamCardStyle.border

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: PicoCreamCardStyle.borderWidth)
            )
            .shadow(
                color: showsShadow ? PicoShadow.raisedCardColor : .clear,
                radius: showsShadow ? PicoShadow.raisedCardRadius : 0,
                x: PicoShadow.raisedCardX,
                y: showsShadow ? PicoShadow.raisedCardY : 0
            )
    }
}

struct PicoCardDivider: View {
    var horizontalPadding: CGFloat = PicoCreamCardStyle.contentPadding

    var body: some View {
        Rectangle()
            .fill(PicoCreamCardStyle.divider)
            .frame(height: PicoCreamCardStyle.borderWidth)
            .padding(.horizontal, horizontalPadding)
    }
}

struct PicoCardModifier: ViewModifier {
    var padding: CGFloat = PicoSpacing.cardPadding
    var cornerRadius: CGFloat = PicoRadius.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PicoColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PicoColors.border, lineWidth: 1)
            )
    }
}

extension View {
    func picoCard(
        padding: CGFloat = PicoSpacing.cardPadding,
        cornerRadius: CGFloat = PicoRadius.large
    ) -> some View {
        modifier(PicoCardModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func picoScreenBackground() -> some View {
        background(PicoColors.appBackground.ignoresSafeArea())
    }

    func picoCreamCard(
        cornerRadius: CGFloat = PicoCreamCardStyle.cornerRadius,
        showsShadow: Bool = true,
        padding: CGFloat? = nil,
        background: Color = PicoCreamCardStyle.background,
        border: Color = PicoCreamCardStyle.border
    ) -> some View {
        modifier(
            PicoCreamCardModifier(
                cornerRadius: cornerRadius,
                showsShadow: showsShadow,
                padding: padding,
                background: background,
                border: border
            )
        )
    }
}

struct PicoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(PicoColors.textOnPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(PicoColors.primary.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
    }
}

struct PicoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(PicoColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(PicoColors.softSurface.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
    }
}

struct PicoCreamBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(PicoColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .fill(PicoCreamCardStyle.background.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PicoCreamCardStyle.cornerRadius, style: .continuous)
                    .stroke(PicoCreamCardStyle.border, lineWidth: PicoCreamCardStyle.borderWidth)
            )
            .opacity(isEnabled ? 1 : 0.62)
    }
}

struct PicoDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PicoTypography.button)
            .foregroundStyle(PicoColors.error)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(PicoColors.destructiveBackground.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
    }
}
