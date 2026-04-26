//
//  AvatarCatalog.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SpriteKit
import SwiftUI

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

struct AvatarIdleAtlasSlot {
    let row: Int
    let column: Int
}

enum AvatarCatalog {
    static let defaultConfig = AvatarConfig()
}

struct AvatarIdleFrames {
    private static let atlasImageName = "Idle_Characters_Set1.1"
    private static let atlasPixelSize = CGSize(width: 1848, height: 1737)
    private static let sheetPixelSize = CGSize(width: 920, height: 575)
    private static let atlasInset: CGFloat = 2
    private static let sheetSpacing: CGFloat = 4
    private static let rowCount = 5
    private static let frameCount = 8

    private let frames: [[SKTexture]]

    init(hat: AvatarHat) {
        let atlasTexture = SKTexture(imageNamed: Self.atlasImageName)
        atlasTexture.filteringMode = .nearest

        frames = (0..<Self.rowCount).map { row in
            (0..<Self.frameCount).map { frame in
                let texture = SKTexture(rect: Self.normalizedFrameRect(hat: hat, row: row, frame: frame), in: atlasTexture)
                texture.filteringMode = .nearest
                return texture
            }
        }
    }

    func frames(forRow row: Int) -> [SKTexture] {
        frames[min(max(row, 0), Self.rowCount - 1)]
    }

    func firstFrame(forRow row: Int = 0) -> SKTexture {
        frames(forRow: row)[0]
    }

    private static func normalizedFrameRect(hat: AvatarHat, row: Int, frame: Int) -> CGRect {
        let slot = hat.atlasSlot
        let framePixelWidth = sheetPixelSize.width / CGFloat(frameCount)
        let framePixelHeight = sheetPixelSize.height / CGFloat(rowCount)
        let framePixelRect = CGRect(
            x: atlasInset
                + CGFloat(slot.column) * (sheetPixelSize.width + sheetSpacing)
                + CGFloat(frame) * framePixelWidth,
            y: atlasInset
                + CGFloat(slot.row) * (sheetPixelSize.height + sheetSpacing)
                + CGFloat(row) * framePixelHeight,
            width: framePixelWidth,
            height: framePixelHeight
        )
        return CGRect(
            x: framePixelRect.minX / atlasPixelSize.width,
            y: (atlasPixelSize.height - framePixelRect.maxY) / atlasPixelSize.height,
            width: framePixelRect.width / atlasPixelSize.width,
            height: framePixelRect.height / atlasPixelSize.height
        )
    }
}

struct AvatarBadgeView: View {
    let config: AvatarConfig
    var size: CGFloat = 56

    private var hat: AvatarHat {
        config.selectedHat
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(hat.color.gradient)

            Image(systemName: hat.systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("\(hat.name) avatar"))
    }
}

struct AvatarPickerView: View {
    @Binding var selection: AvatarConfig

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarHat.allCases) { hat in
                Button {
                    selection = selection.withHat(hat)
                } label: {
                    VStack(spacing: 8) {
                        AvatarBadgeView(config: selection.withHat(hat), size: 58)
                            .overlay {
                                if selection.selectedHat == hat {
                                    Circle()
                                        .stroke(.tint, lineWidth: 3)
                                }
                            }

                        Text(hat.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.selectedHat == hat ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
