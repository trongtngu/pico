//
//  AvatarCatalog.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SpriteKit
import SwiftUI
import UIKit

struct AvatarConfig: Codable, Equatable {
    static let currentVersion = 1
    static let defaultCharacter = "character_0"

    let version: Int
    let character: String
    let hat: Int

    init(
        version: Int = Self.currentVersion,
        character: String = Self.defaultCharacter,
        hat: AvatarHat = .none
    ) {
        self.version = version
        self.character = character
        self.hat = hat.rawValue
    }

    init(key: String) {
        self.init(hat: .none)
    }

    var selectedHat: AvatarHat {
        AvatarHat(rawValue: hat) ?? .none
    }

    func withHat(_ hat: AvatarHat) -> AvatarConfig {
        AvatarConfig(character: character, hat: hat)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case character
        case hat
        case type
        case key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let version = try container.decodeIfPresent(Int.self, forKey: .version),
           let character = try container.decodeIfPresent(String.self, forKey: .character),
           let hatValue = try container.decodeIfPresent(Int.self, forKey: .hat),
           let hat = AvatarHat(rawValue: hatValue) {
            self.init(version: version, character: character, hat: hat)
            return
        }

        if try container.decodeIfPresent(String.self, forKey: .type) == "preset",
           try container.decodeIfPresent(String.self, forKey: .key) != nil {
            self.init(hat: .none)
            return
        }

        self.init(hat: .none)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(character, forKey: .character)
        try container.encode(selectedHat.rawValue, forKey: .hat)
    }
}

enum AvatarHat: Int, CaseIterable, Identifiable, Equatable {
    case none = 0
    case bambooHat = 1
    case beanie = 2
    case bow = 3
    case helmet = 4

    var id: Int { rawValue }

    var requiredScore: Int {
        switch self {
        case .none:
            0
        case .bambooHat:
            3
        case .beanie:
            10
        case .bow:
            20
        case .helmet:
            30
        }
    }

    func isUnlocked(with score: Int) -> Bool {
        score >= requiredScore
    }

    var name: String {
        switch self {
        case .none:
            "No Hat"
        case .bambooHat:
            "Bamboo Hat"
        case .beanie:
            "Beanie"
        case .bow:
            "Bow"
        case .helmet:
            "Helmet"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            "person.crop.circle"
        case .bambooHat:
            "sun.horizon"
        case .beanie:
            "snowflake"
        case .bow:
            "gift"
        case .helmet:
            "shield"
        }
    }

    var color: Color {
        switch self {
        case .none:
            .yellow
        case .bambooHat:
            .orange
        case .beanie:
            .blue
        case .bow:
            .pink
        case .helmet:
            .purple
        }
    }

    var atlasSlot: AvatarIdleAtlasSlot {
        switch self {
        case .none:
            AvatarIdleAtlasSlot(row: 0, column: 0)
        case .bambooHat:
            AvatarIdleAtlasSlot(row: 0, column: 1)
        case .beanie:
            AvatarIdleAtlasSlot(row: 1, column: 0)
        case .bow:
            AvatarIdleAtlasSlot(row: 1, column: 1)
        case .helmet:
            AvatarIdleAtlasSlot(row: 2, column: 0)
        }
    }

    var walkAtlasSlot: AvatarIdleAtlasSlot {
        switch self {
        case .none:
            AvatarIdleAtlasSlot(row: 0, column: 0)
        case .bambooHat:
            AvatarIdleAtlasSlot(row: 0, column: 1)
        case .beanie:
            AvatarIdleAtlasSlot(row: 1, column: 0)
        case .bow:
            AvatarIdleAtlasSlot(row: 2, column: 0)
        case .helmet:
            AvatarIdleAtlasSlot(row: 1, column: 1)
        }
    }
}

enum AvatarScarf: Int, Equatable {
    case green = 2
    case blue = 3
    case orange = 4

    init?(bondLevel: Int) {
        switch bondLevel {
        case 2:
            self = .green
        case 3:
            self = .blue
        case 4...:
            self = .orange
        default:
            return nil
        }
    }

    var idleRegularAtlasImageName: String {
        "Char__Idle_Scarf_\(assetName)_Regular.1"
    }

    var idleHappyAtlasImageName: String {
        "Char__Idle_Scarf_\(assetName)_Happy.1"
    }

    var walkRegularAtlasImageName: String {
        "Char__Walk_Scarf_\(assetName)_Regular.1"
    }

    var assetName: String {
        switch self {
        case .green:
            "Green"
        case .blue:
            "Blue"
        case .orange:
            "Orange"
        }
    }
}

struct AvatarIdleAtlasSlot {
    let row: Int
    let column: Int
}

enum AvatarCatalog {
    static let defaultConfig = AvatarConfig()
}

enum AvatarFinalAtlasKind {
    case idleRegular
    case idleHappy
    case walkRegular

    var baseName: String {
        switch self {
        case .idleRegular:
            "Character_Idle_Regular"
        case .idleHappy:
            "Character_Idle_Happy"
        case .walkRegular:
            "Character_Walk_Regular"
        }
    }

    var rowCount: Int { 5 }

    var frameCount: Int {
        switch self {
        case .idleRegular, .idleHappy:
            8
        case .walkRegular:
            6
        }
    }
}

enum AvatarFinalAtlas {
    private static let directoryName = "Character_Images_Final"

    static func frames(
        kind: AvatarFinalAtlasKind,
        hat: AvatarHat,
        scarf: AvatarScarf?,
        filteringMode: SKTextureFilteringMode
    ) -> [[SKTexture]] {
        let atlas = SKTextureAtlas(named: atlasName(kind: kind, hat: hat, scarf: scarf))
        let frameNames = orderedFrameNames(in: atlas, frameCount: kind.rowCount * kind.frameCount)

        return (0..<kind.rowCount).map { row in
            (0..<kind.frameCount).map { frame in
                let frameIndex = row * kind.frameCount + frame
                let texture = atlas.textureNamed(
                    frameNames.indices.contains(frameIndex)
                        ? frameNames[frameIndex]
                        : frameNames.first ?? ""
                )
                texture.filteringMode = filteringMode
                return texture
            }
        }
    }

    static func portraitImage(hat: AvatarHat, scarf: AvatarScarf?) -> UIImage? {
        let atlas = SKTextureAtlas(named: atlasName(kind: .idleRegular, hat: hat, scarf: scarf))
        guard let firstFrameName = orderedFrameNames(in: atlas, frameCount: 1).first else {
            return nil
        }

        let texture = atlas.textureNamed(firstFrameName)
        texture.filteringMode = .nearest
        let image = UIImage(cgImage: texture.cgImage())
        guard let cgImage = image.cgImage else {
            return image
        }

        let cropRect = CGRect(
            x: 0,
            y: 0,
            width: cgImage.width,
            height: Int(ceil(CGFloat(cgImage.height) * 0.68))
        )
        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: image.imageOrientation)
    }

    static func atlasName(kind: AvatarFinalAtlasKind, hat: AvatarHat, scarf: AvatarScarf?) -> String {
        let baseName = [
            kind.baseName,
            scarf.map { "Scarf_\($0.assetName)" }
        ]
        .compactMap(\.self)
        .joined(separator: "_")

        let candidates = hat.finalAtlasVariantCandidates(kind: kind, scarf: scarf)
            .map { "\(baseName)_\($0)" }

        guard !candidates.isEmpty else {
            return baseName
        }

        for candidate in candidates where atlasExists(candidate) {
            return candidate
        }

        if kind == .idleHappy {
            let regularAtlasName = atlasName(kind: .idleRegular, hat: hat, scarf: scarf)
            if atlasExists(regularAtlasName) {
                return regularAtlasName
            }
        }

        return candidates[0]
    }

    private static func atlasExists(_ atlasName: String) -> Bool {
        Bundle.main.path(forResource: atlasName, ofType: "plist") != nil
            || Bundle.main.path(forResource: atlasName, ofType: "plist", inDirectory: directoryName) != nil
    }

    private static func orderedFrameNames(in atlas: SKTextureAtlas, frameCount: Int) -> [String] {
        let indexedNames = Dictionary(
            uniqueKeysWithValues: atlas.textureNames.compactMap { textureName -> (Int, String)? in
                guard let index = frameIndex(from: textureName) else {
                    return nil
                }
                return (index, textureName)
            }
        )

        if indexedNames.count >= frameCount {
            return (0..<frameCount).compactMap { indexedNames[$0] }
        }

        return atlas.textureNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private static func frameIndex(from textureName: String) -> Int? {
        let name = textureName.hasSuffix(".png")
            ? String(textureName.dropLast(4))
            : textureName
        guard let separatorIndex = name.lastIndex(of: "-") else {
            return nil
        }

        return Int(name[name.index(after: separatorIndex)...])
    }
}

private extension AvatarHat {
    func finalAtlasVariantCandidates(kind: AvatarFinalAtlasKind, scarf: AvatarScarf?) -> [String] {
        switch self {
        case .none:
            return []
        case .bambooHat:
            return ["BambooHat_Beige"]
        case .beanie:
            if kind == .walkRegular, scarf == .green || scarf == .blue {
                return ["Beanie_Blue", "Beanie_Sky"]
            }
            if kind == .idleRegular, scarf == .blue {
                return ["Beanie_Blue", "Beanie_Sky"]
            }
            return ["Beanie_Sky", "Beanie_Blue"]
        case .bow:
            if kind == .idleHappy, scarf == .blue {
                return ["Bow_yellow", "Bow_Yellow"]
            }
            return ["Bow_Yellow", "Bow_yellow"]
        case .helmet:
            return ["Helmet_Silver"]
        }
    }
}

struct AvatarIdleFrames {
    private let frames: [[SKTexture]]

    init(hat: AvatarHat, scarf: AvatarScarf? = nil) {
        frames = AvatarFinalAtlas.frames(
            kind: .idleRegular,
            hat: hat,
            scarf: scarf,
            filteringMode: .nearest
        )
    }

    func frames(forRow row: Int) -> [SKTexture] {
        frames[min(max(row, 0), AvatarFinalAtlasKind.idleRegular.rowCount - 1)]
    }

    func firstFrame(forRow row: Int = 0) -> SKTexture {
        frames(forRow: row)[0]
    }
}

struct AvatarHappyIdleFrames {
    private let frames: [[SKTexture]]

    init(hat: AvatarHat, scarf: AvatarScarf? = nil) {
        frames = AvatarFinalAtlas.frames(
            kind: .idleHappy,
            hat: hat,
            scarf: scarf,
            filteringMode: .nearest
        )
    }

    func frames(forRow row: Int) -> [SKTexture] {
        frames[min(max(row, 0), AvatarFinalAtlasKind.idleHappy.rowCount - 1)]
    }

    func firstFrame(forRow row: Int = 0) -> SKTexture {
        frames(forRow: row)[0]
    }
}

private final class AvatarPortraitImageCache {
    static let shared = AvatarPortraitImageCache()

    private let cache = NSCache<NSNumber, UIImage>()

    func image(for hat: AvatarHat, scarf: AvatarScarf?) -> UIImage? {
        let key = NSNumber(value: hat.rawValue * 10 + (scarf?.rawValue ?? 0))
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let image = Self.makeImage(for: hat, scarf: scarf) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func makeImage(for hat: AvatarHat, scarf: AvatarScarf?) -> UIImage? {
        AvatarFinalAtlas.portraitImage(hat: hat, scarf: scarf)
    }
}

struct AvatarBadgeView: View {
    let config: AvatarConfig
    var size: CGFloat = 56
    var scarf: AvatarScarf? = nil

    private var hat: AvatarHat {
        config.selectedHat
    }

    private var portraitImage: UIImage? {
        AvatarPortraitImageCache.shared.image(for: hat, scarf: scarf)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(hat.color.opacity(portraitImage == nil ? 1 : 0.18).gradient)

            if let portraitImage {
                Image(uiImage: portraitImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: hat.systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: max(1, size * 0.025))
        }
        .accessibilityLabel(Text("\(hat.name) avatar"))
    }
}

struct AvatarPickerView: View {
    @Binding var selection: AvatarConfig
    var score: Int = 0

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarHat.allCases) { hat in
                let isUnlocked = hat.isUnlocked(with: score)

                Button {
                    guard isUnlocked else { return }
                    selection = selection.withHat(hat)
                } label: {
                    VStack(spacing: 8) {
                        AvatarBadgeView(config: selection.withHat(hat), size: 58)
                            .overlay {
                                if selection.selectedHat == hat {
                                    Circle()
                                        .stroke(PicoColors.primary, lineWidth: 3)
                                }
                            }
                            .overlay {
                                if !isUnlocked {
                                    Circle()
                                        .fill(.black.opacity(0.42))

                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }

                        Text(hat.name)
                            .font(.caption)
                            .foregroundStyle(isUnlocked ? PicoColors.textPrimary : PicoColors.textSecondary)
                            .lineLimit(1)

                        Text("\(hat.requiredScore) points")
                            .font(.caption2)
                            .foregroundStyle(PicoColors.textSecondary)
                            .opacity(isUnlocked ? 0 : 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .contentShape(Rectangle())
                    .opacity(isUnlocked ? 1 : 0.72)
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked)
                .accessibilityAddTraits(selection.selectedHat == hat ? .isSelected : [])
                .accessibilityLabel(Text(isUnlocked ? hat.name : "\(hat.name), locked until \(hat.requiredScore) points"))
            }
        }
        .padding(.vertical, 4)
    }
}
