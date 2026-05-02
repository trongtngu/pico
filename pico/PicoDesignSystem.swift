//
//  PicoDesignSystem.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import SwiftUI
#if canImport(CoreText)
import CoreText
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PicoColors {
    static let highlight = Color(hex: 0xE8A75A)
    static let highlightBackground = highlight
    static let highlightBorder = Color(hex: 0xD38F3E)
    static let highlightShadow = Color(hex: 0xE0B883)

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

    static let fishRarityCommon = Color(hex: 0x7A817A)
    static let fishRarityRare = Color(hex: 0xD88A2D)
    static let fishRarityUltraRare = Color(hex: 0x7A4FA3)
}

struct PicoFishRarityStyle {
    let mainColor: Color
    let accentColor: Color
    let pillTextColor: Color
    let pillBackgroundColor: Color
    let rowBackgroundColor: Color
    let rowBorderColor: Color
    let iconFallbackColor: Color

    init(mainColor: Color) {
        self.mainColor = mainColor
        accentColor = mainColor
        pillTextColor = mainColor
        pillBackgroundColor = mainColor.opacity(0.14)
        rowBackgroundColor = mainColor.opacity(0.10)
        rowBorderColor = mainColor.opacity(0.34)
        iconFallbackColor = mainColor
    }
}

extension FishRarity {
    var picoStyle: PicoFishRarityStyle {
        switch self {
        case .common:
            PicoFishRarityStyle(mainColor: PicoColors.fishRarityCommon)
        case .rare:
            PicoFishRarityStyle(mainColor: PicoColors.fishRarityRare)
        case .ultraRare:
            PicoFishRarityStyle(mainColor: PicoColors.fishRarityUltraRare)
        }
    }
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
    static let screenTitle = primary(size: 42, weight: .bold)
    static let sectionTitle = primary(size: 26, weight: .bold)
    static let topBarTitle = primary(size: 24, weight: .bold)
    static let cardTitle = primary(size: 21, weight: .bold)
    static let compactTitle = primary(size: 20, weight: .bold)
    static let actionTitle = primary(size: 22, weight: .bold)
    static let largeValue = primary(size: 44, weight: .bold)
    static let durationValue = primary(size: 40, weight: .bold)
    static let fishName = primary(size: 28, weight: .bold)
    static let countValue = primary(size: 22, weight: .bold)
    static let primaryLabel = primary(size: 17, weight: .bold)
    static let primaryLabelSemibold = primary(size: 17, weight: .semibold)
    static let statusLabel = primary(size: 14, weight: .semibold)
    static let smallAction = primary(size: 14, weight: .bold)
    static let badgeCount = primary(size: 11, weight: .bold)
    static let body = secondary(size: 17, weight: .regular)
    static let bodySemibold = secondary(size: 17, weight: .semibold)
    static let caption = secondary(size: 14, weight: .medium)
    static let captionSemibold = secondary(size: 14, weight: .semibold)
    static let compactCaption = secondary(size: 13, weight: .medium)
    static let tinyCaption = secondary(size: 11, weight: .medium)
    static let tinyCaptionBold = secondary(size: 11, weight: .bold)
    static let pill = primary(size: 13, weight: .bold)
    static let largePill = primary(size: 15, weight: .bold)
    static let compactValue = primary(size: 16, weight: .bold)
    static let inlineValue = primary(size: 17, weight: .bold)
    static let tabLabel = primary(size: 13, weight: .semibold)
    static let button = primary(size: 17, weight: .bold)

    static func primary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        PicoFontRegistrar.registerFontsIfNeeded()
        return Font.custom(PicoFontName.quicksand(weight), size: size)
    }

    static func secondary(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        PicoFontRegistrar.registerFontsIfNeeded()
        return Font.custom(PicoFontName.splineSans(weight), size: size)
    }

    static func symbol(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

private enum PicoFontName {
    static func quicksand(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            "Quicksand-Light"
        case .medium:
            "Quicksand-Medium"
        case .semibold:
            "Quicksand-SemiBold"
        case .bold, .heavy, .black:
            "Quicksand-Bold"
        default:
            "Quicksand-Regular"
        }
    }

    static func splineSans(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            "SplineSans-Light"
        case .medium:
            "SplineSans-Medium"
        case .semibold:
            "SplineSans-SemiBold"
        case .bold, .heavy, .black:
            "SplineSans-Bold"
        default:
            "SplineSans-Regular"
        }
    }
}

private enum PicoFontRegistrar {
    static func registerFontsIfNeeded() {
        _ = registeredFonts
    }

    private static let registeredFonts: Void = {
        #if canImport(CoreText)
        let fontFiles = [
            "Quicksand-Light",
            "Quicksand-Regular",
            "Quicksand-Medium",
            "Quicksand-SemiBold",
            "Quicksand-Bold",
            "SplineSans-Light",
            "SplineSans-Regular",
            "SplineSans-Medium",
            "SplineSans-SemiBold",
            "SplineSans-Bold"
        ]
        let fontDirectories: [String?] = [
            nil,
            "fonts/Quicksand_Complete/Fonts/OTF",
            "fonts/SplineSans_Complete/Fonts/OTF"
        ]

        for fontFile in fontFiles {
            guard let fontURL = fontDirectories.compactMap({
                Bundle.main.url(forResource: fontFile, withExtension: "otf", subdirectory: $0)
            }).first else {
                continue
            }

            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        #endif
    }()
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

enum PicoIconAsset: String {
    case bars3Solid = "bars-3_solid"
    case buildingStorefrontRegular = "building-storefront_regular"
    case buildingStorefrontSolid = "building-storefront_solid"
    case chevronLeftRegular = "chevron-left_regular"
    case chevronRightRegular = "chevron-right_regular"
    case clockRegular = "clock_regular"
    case envelopeRegular = "envelope_regular"
    case fireRegular = "fire_regular"
    case fireSolid = "fire_solid"
    case homeRegular = "home_regular"
    case homeSolid = "home_solid"
    case inboxRegular = "inbox_regular"
    case infoRegular = "info_regular"
    case logoutRegular = "logout_regular"
    case magnifyingGlassRegular = "magnifying-glass_regular"
    case paperAirplaneRegular = "paper-airplane_regular"
    case pencilRegular = "pencil_regular"
    case sparklesRegular = "sparkles_regular"
    case sparklesSolid = "sparkles_solid"
    case userCircleRegular = "user_circle_regular"
    case userCircleSolid = "user-circle_solid"
    case userGroupRegular = "user_group_regular"
    case userGroupSolid = "user-group_solid"
    case userPlusRegular = "user_plus_regular"
    case usersRegular = "users_regular"
    case usersSolid = "users_solid"
    case xMarkRegular = "x-mark_regular"
}

struct PicoIcon: View {
    let asset: PicoIconAsset
    var size: CGFloat

    init(_ asset: PicoIconAsset, size: CGFloat = 20) {
        self.asset = asset
        self.size = size
    }

    var body: some View {
        Image(asset.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
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

enum PicoNavigationBarAppearance {
    static func configure() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = PicoUIColors.appBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: PicoUIColors.textPrimary]
        appearance.largeTitleTextAttributes = [.foregroundColor: PicoUIColors.textPrimary]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = PicoUIColors.textPrimary
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
