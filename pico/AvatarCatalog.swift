//
//  AvatarCatalog.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SwiftUI

struct AvatarConfig: Codable, Equatable {
    let type: String
    let key: String

    init(key: String) {
        self.type = "preset"
        self.key = key
    }
}

struct AvatarPreset: Identifiable, Equatable {
    let key: String
    let name: String
    let systemImage: String
    let colorName: String

    var id: String { key }
}

enum AvatarCatalog {
    static let presets = [
        AvatarPreset(key: "avatar_1", name: "Bolt", systemImage: "bolt.fill", colorName: "yellow"),
        AvatarPreset(key: "avatar_2", name: "Leaf", systemImage: "leaf.fill", colorName: "green"),
        AvatarPreset(key: "avatar_3", name: "Moon", systemImage: "moon.fill", colorName: "indigo"),
        AvatarPreset(key: "avatar_4", name: "Spark", systemImage: "sparkles", colorName: "pink")
    ]

    static let defaultConfig = AvatarConfig(key: presets[0].key)

    static func preset(for config: AvatarConfig) -> AvatarPreset {
        presets.first { $0.key == config.key } ?? presets[0]
    }
}

extension AvatarPreset {
    var color: Color {
        switch colorName {
        case "yellow":
            .yellow
        case "green":
            .green
        case "indigo":
            .indigo
        case "pink":
            .pink
        default:
            .accentColor
        }
    }
}

struct AvatarBadgeView: View {
    let config: AvatarConfig
    var size: CGFloat = 56

    private var preset: AvatarPreset {
        AvatarCatalog.preset(for: config)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(preset.color.gradient)

            Image(systemName: preset.systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text("\(preset.name) avatar"))
    }
}

struct AvatarPickerView: View {
    @Binding var selection: AvatarConfig

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarCatalog.presets) { preset in
                Button {
                    selection = AvatarConfig(key: preset.key)
                } label: {
                    VStack(spacing: 8) {
                        AvatarBadgeView(config: AvatarConfig(key: preset.key), size: 58)
                            .overlay {
                                if selection.key == preset.key {
                                    Circle()
                                        .stroke(.tint, lineWidth: 3)
                                }
                            }

                        Text(preset.name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.key == preset.key ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
