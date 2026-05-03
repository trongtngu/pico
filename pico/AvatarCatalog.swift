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

enum AvatarHat: Int, CaseIterable, Identifiable, Hashable {
    case none = 0
    case bambooHat = 1
    case beanie = 2
    case bow = 3
    case helmet = 4

    var id: Int { rawValue }

    var berryCost: Int {
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

    func isOwned(in ownedHats: Set<AvatarHat>) -> Bool {
        self == .none || ownedHats.contains(self)
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

}

enum AvatarScarf: Int, Equatable {
    case green = 2
    case blue = 3
    case orange = 4
    case purple = 5

    init?(bondLevel: Int) {
        switch bondLevel {
        case 2:
            self = .green
        case 3:
            self = .blue
        case 4:
            self = .orange
        case 5...:
            self = .purple
        default:
            return nil
        }
    }

    var assetName: String {
        switch self {
        case .green:
            "Green"
        case .blue:
            "Blue"
        case .orange:
            "Orange"
        case .purple:
            "Purple"
        }
    }
}

enum AvatarCatalog {
    static let defaultConfig = AvatarConfig()
}

enum AvatarFinalAtlasKind {
    case idleRegular
    case idleHappy
    case walkRegular
    case fishing

    var rawBaseName: String {
        switch self {
        case .idleRegular:
            "Char_Idle_Regular"
        case .idleHappy:
            "Char_Idle_Happy"
        case .walkRegular:
            "Char_Walk_Regular"
        case .fishing:
            "Layer0_Body_Blank"
        }
    }

    var motionName: String {
        switch self {
        case .idleRegular, .idleHappy:
            "Idle"
        case .walkRegular:
            "Walk"
        case .fishing:
            "Fishing"
        }
    }

    var rowCount: Int { 5 }

    var frameCount: Int {
        switch self {
        case .idleRegular, .idleHappy:
            8
        case .walkRegular, .fishing:
            6
        }
    }
}

struct AvatarTextureLayer {
    let frames: [[SKTexture]]
}

struct AvatarLayeredFrames {
    let rowCount: Int
    let frameCount: Int
    let layers: [AvatarTextureLayer]

    func textures(forRow row: Int) -> [[SKTexture]] {
        let clampedRow = min(max(row, 0), rowCount - 1)
        return layers.map { $0.frames[clampedRow] }
    }

    func firstTextures(forRow row: Int = 0) -> [SKTexture] {
        textures(forRow: row).compactMap(\.first)
    }
}

enum AvatarLayeredAtlas {
    static func frames(
        kind: AvatarFinalAtlasKind,
        hat: AvatarHat,
        scarf: AvatarScarf?,
        filteringMode: SKTextureFilteringMode
    ) -> AvatarLayeredFrames {
        if kind == .fishing {
            return fishingFrames(
                hat: hat,
                scarf: scarf,
                filteringMode: filteringMode
            )
        }

        let layers = rawLayerNames(kind: kind, hat: hat, scarf: scarf).map { rawLayerName in
            AvatarTextureLayer(
                frames: sheetFrames(
                    rawLayerName: rawLayerName,
                    kind: kind,
                    filteringMode: filteringMode
                )
            )
        }

        return AvatarLayeredFrames(
            rowCount: kind.rowCount,
            frameCount: kind.frameCount,
            layers: layers
        )
    }

    private static func fishingFrames(
        hat: AvatarHat,
        scarf: AvatarScarf?,
        filteringMode: SKTextureFilteringMode
    ) -> AvatarLayeredFrames {
        var layers = [
            textureLayer(named: "NegativeLayer_FishingPole_Wood", kind: .fishing, filteringMode: filteringMode),
            textureLayer(named: "Layer0_Body_Blank", kind: .fishing, filteringMode: filteringMode),
            textureLayer(named: "Layer1_Face_Regular", kind: .fishing, filteringMode: filteringMode)
        ]

        if let scarf {
            layers.append(textureLayer(named: "Layer9_Scarf_\(scarf.fishingRawLayerName)", kind: .fishing, filteringMode: filteringMode))
        }
        if let hatLayerName = hat.rawLayerName {
            layers.append(textureLayer(named: "Layer11_\(hatLayerName)", kind: .fishing, filteringMode: filteringMode))
        }
        layers.append(textureLayer(named: "Layer13_FishingPole_Wood", kind: .fishing, filteringMode: filteringMode))

        return AvatarLayeredFrames(
            rowCount: AvatarFinalAtlasKind.fishing.rowCount,
            frameCount: AvatarFinalAtlasKind.fishing.frameCount,
            layers: layers
        )
    }

    private static func textureLayer(
        named rawLayerName: String,
        kind: AvatarFinalAtlasKind,
        filteringMode: SKTextureFilteringMode
    ) -> AvatarTextureLayer {
        AvatarTextureLayer(
            frames: sheetFrames(
                rawLayerName: rawLayerName,
                kind: kind,
                filteringMode: filteringMode
            )
        )
    }

    static func portraitImage(hat: AvatarHat, scarf: AvatarScarf?) -> UIImage? {
        let layerTextures = frames(
            kind: .idleRegular,
            hat: hat,
            scarf: scarf,
            filteringMode: .nearest
        ).firstTextures()
        guard !layerTextures.isEmpty else { return nil }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: rawFrameSize, height: rawFrameSize),
            format: rendererFormat
        )
        let image = renderer.image { _ in
            for texture in layerTextures {
                UIImage(cgImage: texture.cgImage()).draw(
                    in: CGRect(x: 0, y: 0, width: rawFrameSize, height: rawFrameSize)
                )
            }
        }
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

    private static let rawFrameSize: CGFloat = 460

    private static func normalizedFrameRect(
        row: Int,
        column: Int,
        rowCount: Int,
        columnCount: Int
    ) -> CGRect {
        let frameWidth = 1 / CGFloat(columnCount)
        let frameHeight = 1 / CGFloat(rowCount)
        return CGRect(
            x: CGFloat(column) * frameWidth,
            y: 1 - CGFloat(row + 1) * frameHeight,
            width: frameWidth,
            height: frameHeight
        )
    }

    private static func rawLayerNames(
        kind: AvatarFinalAtlasKind,
        hat: AvatarHat,
        scarf: AvatarScarf?
    ) -> [String] {
        var layerNames = [kind.rawBaseName]
        if let scarf {
            layerNames.append("Layer9_Scarf_\(scarf.rawLayerName(for: kind))_\(kind.motionName)")
        }
        if let hatLayerName = hat.rawLayerName {
            layerNames.append("Layer11_\(hatLayerName)_\(kind.motionName)")
        }
        return layerNames
    }

    private static func sheetFrames(
        rawLayerName: String,
        kind: AvatarFinalAtlasKind,
        filteringMode: SKTextureFilteringMode
    ) -> [[SKTexture]] {
        let atlas = atlas(named: rawLayerName, kind: kind)
        let textureName = atlas.textureNames.first ?? "\(rawLayerName).png"
        let sheetTexture = atlas.textureNamed(textureName)
        sheetTexture.filteringMode = filteringMode

        return (0..<kind.rowCount).map { row in
            (0..<kind.frameCount).map { column in
                let texture = SKTexture(
                    rect: normalizedFrameRect(
                        row: row,
                        column: column,
                        rowCount: kind.rowCount,
                        columnCount: kind.frameCount
                    ),
                    in: sheetTexture
                )
                texture.filteringMode = filteringMode
                return texture
            }
        }
    }

    private static func atlas(named rawLayerName: String, kind: AvatarFinalAtlasKind) -> SKTextureAtlas {
        let nestedAtlas = SKTextureAtlas(named: atlasName(for: rawLayerName, kind: kind))
        if !nestedAtlas.textureNames.isEmpty {
            return nestedAtlas
        }

        return SKTextureAtlas(named: rawLayerName)
    }

    private static func atlasName(for rawLayerName: String, kind: AvatarFinalAtlasKind) -> String {
        switch kind {
        case .fishing:
            "Atlases/Fishing/\(rawLayerName)"
        case .idleRegular, .idleHappy, .walkRegular:
            "Atlases/Character_Sheets_Raw/\(rawLayerName)"
        }
    }
}

private extension AvatarHat {
    var rawLayerName: String? {
        switch self {
        case .none:
            nil
        case .bambooHat:
            "BambooHat_Beige"
        case .beanie:
            "Beanie_Sky"
        case .bow:
            "Bow_Yellow"
        case .helmet:
            "Helmet_Silver"
        }
    }
}

private extension AvatarScarf {
    func rawLayerName(for kind: AvatarFinalAtlasKind) -> String {
        if kind == .fishing {
            return fishingRawLayerName
        }

        return switch self {
        case .green:
            "Green"
        case .blue:
            "Sky"
        case .orange:
            "Orange"
        case .purple:
            "Purple"
        }
    }

    var fishingRawLayerName: String {
        switch self {
        case .green:
            "Olive"
        case .blue:
            "Sky"
        case .orange:
            "Orange"
        case .purple:
            "Orange"
        }
    }
}

final class AvatarLayeredSpriteNode: SKNode {
    private var layerNodes: [SKSpriteNode] = []

    var spriteSize: CGSize = .zero {
        didSet {
            applyLayout()
        }
    }

    var anchorPoint = CGPoint(x: 0.5, y: 0.5) {
        didSet {
            applyLayout()
        }
    }

    init(frames: AvatarLayeredFrames, row: Int = 0) {
        super.init()
        setFirstFrame(frames: frames, row: row)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func setFirstFrame(frames: AvatarLayeredFrames, row: Int = 0) {
        let textures = frames.firstTextures(forRow: row)
        ensureLayerNodes(count: textures.count)
        for (index, texture) in textures.enumerated() {
            layerNodes[index].texture = texture
        }
    }

    func runAnimation(
        with frames: AvatarLayeredFrames,
        row: Int,
        timePerFrame: TimeInterval,
        key: String,
        delayBetweenCycles: TimeInterval = 0
    ) {
        let layerTextures = frames.textures(forRow: row)
        ensureLayerNodes(count: layerTextures.count)
        for (index, textures) in layerTextures.enumerated() {
            let animation = SKAction.animate(with: textures, timePerFrame: timePerFrame)
            let action: SKAction
            if delayBetweenCycles > 0 {
                action = .repeatForever(.sequence([animation, .wait(forDuration: delayBetweenCycles)]))
            } else {
                action = .repeatForever(animation)
            }
            layerNodes[index].run(
                action,
                withKey: key
            )
        }
    }

    func removeAnimation(forKey key: String) {
        for layerNode in layerNodes {
            layerNode.removeAction(forKey: key)
        }
    }

    func hasAnimation(forKey key: String) -> Bool {
        layerNodes.contains { $0.action(forKey: key) != nil }
    }

    private func ensureLayerNodes(count: Int) {
        while layerNodes.count > count {
            layerNodes.removeLast().removeFromParent()
        }
        while layerNodes.count < count {
            let layerNode = SKSpriteNode()
            layerNode.zPosition = CGFloat(layerNodes.count)
            layerNodes.append(layerNode)
            addChild(layerNode)
        }
        applyLayout()
    }

    private func applyLayout() {
        for layerNode in layerNodes {
            layerNode.anchorPoint = anchorPoint
            layerNode.size = spriteSize
        }
    }
}

struct AvatarIdleFrames {
    let layeredFrames: AvatarLayeredFrames

    init(hat: AvatarHat, scarf: AvatarScarf? = nil) {
        layeredFrames = AvatarLayeredAtlas.frames(
            kind: .idleRegular,
            hat: hat,
            scarf: scarf,
            filteringMode: .nearest
        )
    }
}

struct AvatarHappyIdleFrames {
    let layeredFrames: AvatarLayeredFrames

    init(hat: AvatarHat, scarf: AvatarScarf? = nil) {
        layeredFrames = AvatarLayeredAtlas.frames(
            kind: .idleHappy,
            hat: hat,
            scarf: scarf,
            filteringMode: .nearest
        )
    }
}

struct AvatarFishingFrames {
    let layeredFrames: AvatarLayeredFrames

    init(hat: AvatarHat, scarf: AvatarScarf? = nil, filteringMode: SKTextureFilteringMode = .nearest) {
        layeredFrames = AvatarLayeredAtlas.frames(
            kind: .fishing,
            hat: hat,
            scarf: scarf,
            filteringMode: filteringMode
        )
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
        AvatarLayeredAtlas.portraitImage(hat: hat, scarf: scarf)
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
                    .foregroundStyle(PicoColors.textOnPrimary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(PicoColors.textOnPrimary.opacity(0.28), lineWidth: max(1, size * 0.025))
        }
        .accessibilityLabel(Text("\(hat.name) avatar"))
    }
}

struct AvatarPickerView: View {
    @Binding var selection: AvatarConfig
    var ownedHats: Set<AvatarHat> = [.none]

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarHat.allCases) { hat in
                let isOwned = hat.isOwned(in: ownedHats)

                Button {
                    guard isOwned else { return }
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
                                if !isOwned {
                                    Circle()
                                        .fill(.black.opacity(0.42))

                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(PicoColors.textOnPrimary)
                                }
                            }

                        Text(hat.name)
                            .font(.caption)
                            .foregroundStyle(isOwned ? PicoColors.textPrimary : PicoColors.textSecondary)
                            .lineLimit(1)

                        Text("Not owned")
                            .font(.caption2)
                            .foregroundStyle(PicoColors.textSecondary)
                            .opacity(isOwned ? 0 : 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .contentShape(Rectangle())
                    .opacity(isOwned ? 1 : 0.72)
                }
                .buttonStyle(.plain)
                .disabled(!isOwned)
                .accessibilityAddTraits(selection.selectedHat == hat ? .isSelected : [])
                .accessibilityLabel(Text(isOwned ? hat.name : "\(hat.name), not owned"))
            }
        }
        .padding(.vertical, 4)
    }
}
