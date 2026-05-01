//
//  VillageViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SpriteKit
import SwiftUI

struct VillagePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore
    @EnvironmentObject private var berryStore: BerryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                VillageView(
                    residents: villageStore.residents,
                    currentUserProfile: sessionStore.profile,
                    berryCount: berryStore.balance.berries,
                    pendingRewardSummary: berryStore.pendingRewardSummary
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: 430)
                    .padding(.horizontal, 6)

                if villageStore.isLoadingResidents {
                    HStack {
                        Text("Loading village")
                        Spacer()
                        ProgressView()
                    }
                    .padding(.horizontal)
                }

                if let notice = villageStore.notice {
                    Text(notice)
                        .foregroundStyle(PicoColors.textSecondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Village")
        .task {
            await villageStore.loadResidents(for: sessionStore.session)
        }
        .refreshable {
            await villageStore.loadResidents(for: sessionStore.session)
        }
    }
}

struct VillageView: View {
    let residents: [VillageResident]
    let currentUserProfile: UserProfile?
    let berryCount: Int
    let pendingRewardSummary: BerryRewardSummary

    private static let gridSize = 6
    private static let berryBushCount = 3
    private var gridResidents: [VillageResident] {
        guard let currentUserProfile else { return residents }

        let currentUserResident = VillageResident(
            profile: currentUserProfile,
            bondLevel: 0,
            completedPairSessions: 0,
            unlockedAt: nil
        )
        return [currentUserResident] + residents.filter { $0.profile.userID != currentUserProfile.userID }
    }

    private var sceneID: String {
        let residentID = gridResidents
            .map { "\($0.id.uuidString)-\($0.profile.avatarConfig.selectedHat.rawValue)-\($0.bondLevel)" }
            .joined(separator: "|")
        let bushRewards = pendingRewardSummary.bushBerryTiers.map(String.init(describing:)).joined(separator: "|")
        return "\(berryCount)-\(bushRewards)-\(Self.berryBushCount)-\(rewardSeed)-\(residentID)"
    }

    private var rewardSeed: String {
        currentUserProfile?.userID.uuidString
            ?? gridResidents.map(\.id.uuidString).joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: VillageScene(
                    size: proxy.size,
                    gridSize: Self.gridSize,
                    residents: gridResidents,
                    berryCount: berryCount,
                    pendingRewardSummary: pendingRewardSummary,
                    berryBushCount: Self.berryBushCount,
                    rewardSeed: rewardSeed
                ),
                options: [.allowsTransparency]
            )
            .id(sceneID)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
            .accessibilityLabel(Text("Village grid"))
        }
    }
}

private struct TileCoordinate: Hashable, Identifiable {
    let row: Int
    let column: Int

    var id: String {
        "\(row)-\(column)"
    }

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    static func all(in gridSize: Int) -> [TileCoordinate] {
        (0..<gridSize).flatMap { row in
            (0..<gridSize).map { column in
                TileCoordinate(row: row, column: column)
            }
        }
    }

    func zPosition(in gridSize: Int) -> CGFloat {
        let stableTieBreaker = CGFloat(column) / CGFloat(max(gridSize, 1)) * 0.01
        return CGFloat(row + column) + stableTieBreaker
    }

}

private final class VillageScene: SKScene {
    private static let tileAnchorPoint = CGPoint(x: 0.5, y: 0.71)

    private let gridSize: Int
    private let residents: [VillageResident]
    private let berryCount: Int
    private let pendingRewardSummary: BerryRewardSummary
    private let berryBushCount: Int
    private let rewardSeed: String
    private var renderedSize: CGSize = .zero
    private var villagers: [VillagerNode] = []
    private var lastUpdateTime: TimeInterval?

    init(size: CGSize, gridSize: Int, residents: [VillageResident], berryCount: Int, pendingRewardSummary: BerryRewardSummary, berryBushCount: Int, rewardSeed: String) {
        self.gridSize = gridSize
        self.residents = Array(residents.prefix(gridSize * gridSize))
        self.berryCount = berryCount
        self.pendingRewardSummary = pendingRewardSummary
        self.berryBushCount = berryBushCount
        self.rewardSeed = rewardSeed
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
        villagers.removeAll()
        lastUpdateTime = nil
        drawGrid()
        drawBerryBushes()
        drawVillagers()
    }

    private func drawGrid() {
        let layout = VillageSceneLayout(
            size: size,
            gridSize: gridSize,
            tileAnchorPoint: Self.tileAnchorPoint
        )
        let atlas = SKTextureAtlas(named: "GrassBlock_New")
        let grassBlockTextures = Self.textures(
            named: ["GrassBlock_1.png", "GrassBlock_2.png", "GrassBlock_3.png"],
            in: atlas
        )
        let flowerAtlas = SKTextureAtlas(named: "GrassBlocks_Flowers")
        let flowerTextures = Self.textures(
            named: [
                "GrassBlock_Flowers_Blue_1.png",
                "GrassBlock_Flowers_Blue_2.png",
                "GrassBlock_Flowers_Blue_3.png",
                "GrassBlock_Flowers_Pink_1.png",
                "GrassBlock_Flowers_Pink_2.png",
                "GrassBlock_Flowers_Pink_3.png",
                "GrassBlock_Flowers_White_1.png",
                "GrassBlock_Flowers_White_2.png",
                "GrassBlock_Flowers_White_3.png",
                "GrassBlock_Flowers_Yellow_1.png",
                "GrassBlock_Flowers_Yellow_2.png",
                "GrassBlock_Flowers_Yellow_3.png"
            ],
            in: flowerAtlas
        )
        let rewardTextures = rewardTexturesByTile(flowerTextures: flowerTextures)

        for tile in TileCoordinate.all(in: gridSize) {
            let texture = rewardTextures[tile] ?? grassTexture(for: tile, textures: grassBlockTextures)
            addTileSprite(texture: texture, tile: tile, layout: layout)
        }
    }

    private static func textures(named names: [String], in atlas: SKTextureAtlas) -> [SKTexture] {
        names.map { name in
            let texture = atlas.textureNamed(name)
            texture.filteringMode = .linear
            return texture
        }
    }

    private func rewardTexturesByTile(flowerTextures: [SKTexture]) -> [TileCoordinate: SKTexture] {
        guard berryCount > 0, !flowerTextures.isEmpty else { return [:] }

        var generator = SeededRandomNumberGenerator(seed: StableHash.value(for: "reward-\(rewardSeed)"))
        var tiles = TileCoordinate.all(in: gridSize)
        tiles.shuffle(using: &generator)

        let rewardCount = min(berryCount, tiles.count)
        return Dictionary(uniqueKeysWithValues: tiles.prefix(rewardCount).map { tile in
            let texture = flowerTextures[Int(generator.next() % UInt64(flowerTextures.count))]
            return (tile, texture)
        })
    }

    private func grassTexture(for tile: TileCoordinate, textures: [SKTexture]) -> SKTexture {
        let fallback = textures[0]
        guard textures.count > 1 else { return fallback }

        let seed = StableHash.value(for: "grass-\(rewardSeed)-\(tile.row)-\(tile.column)")
        return textures[Int(seed % UInt64(textures.count))]
    }

    private func addTileSprite(
        texture: SKTexture,
        tile: TileCoordinate,
        layout: VillageSceneLayout
    ) {
        let center = layout.center(for: tile)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = layout.tileAnchorPoint
        sprite.size = CGSize(width: layout.tileWidth, height: layout.tileWidth)
        sprite.position = center
        sprite.zPosition = -center.y - 1_000
        addChild(sprite)
    }

    private func drawBerryBushes() {
        guard berryBushCount > 0 else { return }

        let layout = VillageSceneLayout(
            size: size,
            gridSize: gridSize,
            tileAnchorPoint: Self.tileAnchorPoint
        )
        let placements = [
            BerryBushPlacement(tile: TileCoordinate(row: 1, column: 1), offset: CGPoint(x: -0.18, y: -0.06)),
            BerryBushPlacement(tile: TileCoordinate(row: 1, column: max(1, gridSize - 2)), offset: CGPoint(x: 0.16, y: -0.10)),
            BerryBushPlacement(tile: TileCoordinate(row: max(1, gridSize - 2), column: 2), offset: CGPoint(x: -0.08, y: -0.08))
        ]
        let baseAtlas = SKTextureAtlas(named: "Bushes")
        let berryTiers = Array(pendingRewardSummary.bushBerryTiers.prefix(berryBushCount))

        for (index, placement) in placements.prefix(berryBushCount).enumerated() {
            let position = layout.characterPosition(for: placement.tile)
            let bush = SKNode()
            bush.position = CGPoint(
                x: position.x + layout.tileWidth * placement.offset.x,
                y: position.y + layout.tileWidth * placement.offset.y
            )
            bush.zPosition = -position.y

            let bushNumber = index + 1
            let bushSize = CGSize(width: layout.characterSize * 0.74, height: layout.characterSize * 1.48)
            let baseTexture = baseAtlas.textureNamed("Bush_BerryBush\(bushNumber).png")
            baseTexture.filteringMode = .linear
            let baseSprite = SKSpriteNode(texture: baseTexture)
            baseSprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            baseSprite.size = bushSize
            bush.addChild(baseSprite)

            if index < berryTiers.count {
                let tier = berryTiers[index]
                let berryAtlas = SKTextureAtlas(named: tier.bushAtlasName)
                let berryTexture = berryAtlas.textureNamed("Bush_BerryBush\(bushNumber)_\(tier.bushTextureSuffix).png")
                berryTexture.filteringMode = .linear
                let berrySprite = SKSpriteNode(texture: berryTexture)
                berrySprite.anchorPoint = baseSprite.anchorPoint
                berrySprite.size = bushSize
                berrySprite.zPosition = 1
                bush.addChild(berrySprite)
            }

            addChild(bush)
        }
    }

    private func drawVillagers() {
        let layout = VillageSceneLayout(
            size: size,
            gridSize: gridSize,
            tileAnchorPoint: Self.tileAnchorPoint
        )
        for (index, resident) in residents.enumerated() {
            let tile = startingTile(for: index)
            let startPosition = layout.characterPosition(for: tile)
            let selectedHat = resident.profile.avatarConfig.selectedHat
            let scarf = AvatarScarf(bondLevel: resident.bondLevel)
            let idleFrames = AvatarIdleFrames(hat: selectedHat, scarf: scarf)
            let walkFrames = VillagerWalkFrames(hat: selectedHat, scarf: scarf)
            let villager = VillagerNode(
                currentPosition: startPosition,
                walkFrames: walkFrames,
                idleFrames: idleFrames,
                characterSize: layout.characterSize,
                speed: layout.characterSpeed
            )
            addChild(villager)
            villager.scheduleInitialTarget()
            villagers.append(villager)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard let lastUpdateTime else {
            self.lastUpdateTime = currentTime
            return
        }

        let deltaTime = min(CGFloat(currentTime - lastUpdateTime), 1 / 20)
        self.lastUpdateTime = currentTime

        let layout = VillageSceneLayout(
            size: size,
            gridSize: gridSize,
            tileAnchorPoint: Self.tileAnchorPoint
        )

        for villager in villagers {
            villager.update(
                currentTime: currentTime,
                deltaTime: deltaTime,
                layout: layout
            )
        }
    }

    private func startingTile(for index: Int) -> TileCoordinate {
        let linearPosition = (index + gridSize * 2 + 3) % (gridSize * gridSize)
        let row = linearPosition / gridSize
        let column = linearPosition % gridSize
        return TileCoordinate(row: row, column: column)
    }
}

private struct BerryBushPlacement {
    let tile: TileCoordinate
    let offset: CGPoint
}

private extension BerryBushBerryTier {
    var bushAtlasName: String {
        switch self {
        case .black:
            "Berries_Black"
        case .white:
            "Berries_White"
        case .red:
            "Berries_Red"
        }
    }

    var bushTextureSuffix: String {
        switch self {
        case .black:
            "BerriesBlack"
        case .white:
            "BerriesWhite"
        case .red:
            "BerriesRed"
        }
    }
}

private final class VillagerNode: SKNode {
    private static let walkActionKey = "walk"
    private static let idleActionKey = "idle"

    private let sprite: AvatarLayeredSpriteNode
    private let walkFrames: VillagerWalkFrames
    private let idleFrames: AvatarIdleFrames
    private var currentAnimationDirection: VillagerWalkDirection?
    private var nextTargetTime: TimeInterval = 0
    private var isMoving = false

    private(set) var currentPosition: CGPoint
    private(set) var targetPosition: CGPoint
    private(set) var velocity: CGVector = .zero
    private let movementSpeed: CGFloat

    init(
        currentPosition: CGPoint,
        walkFrames: VillagerWalkFrames,
        idleFrames: AvatarIdleFrames,
        characterSize: CGFloat,
        speed: CGFloat
    ) {
        self.currentPosition = currentPosition
        self.targetPosition = currentPosition
        self.walkFrames = walkFrames
        self.idleFrames = idleFrames
        self.sprite = AvatarLayeredSpriteNode(frames: idleFrames.layeredFrames)
        self.movementSpeed = speed
        super.init()

        position = currentPosition
        zPosition = -currentPosition.y
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.12)
        sprite.spriteSize = CGSize(width: characterSize, height: characterSize)
        addChild(sprite)
        startIdle()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func scheduleInitialTarget() {
        nextTargetTime = 0
    }

    func update(currentTime: TimeInterval, deltaTime: CGFloat, layout: VillageSceneLayout) {
        if nextTargetTime == 0 {
            nextTargetTime = currentTime + TimeInterval.random(in: 0.2...1.0)
        }

        if !isMoving, currentTime >= nextTargetTime {
            chooseRandomTarget(layout: layout, currentTime: currentTime)
        }

        guard isMoving else { return }

        let dx = targetPosition.x - currentPosition.x
        let dy = targetPosition.y - currentPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= 2 else {
            arrive(at: currentTime)
            return
        }

        let normalizedX = dx / distance
        let normalizedY = dy / distance
        let stepDistance = movementSpeed * deltaTime
        if stepDistance >= distance {
            currentPosition = targetPosition
            position = currentPosition
            velocity = .zero
            arrive(at: currentTime)
        } else {
            velocity = CGVector(dx: normalizedX * movementSpeed, dy: normalizedY * movementSpeed)
            currentPosition.x += normalizedX * stepDistance
            currentPosition.y += normalizedY * stepDistance
            position = currentPosition
            zPosition = -position.y
            updateAnimation(dx: dx, dy: dy)
        }
    }

    private func chooseRandomTarget(layout: VillageSceneLayout, currentTime: TimeInterval) {
        let nextPosition = layout.randomCharacterPosition()
        guard hypot(nextPosition.x - currentPosition.x, nextPosition.y - currentPosition.y) >= 2 else {
            nextTargetTime = currentTime + TimeInterval.random(in: 0.25...0.75)
            return
        }

        targetPosition = nextPosition
        isMoving = true
        updateAnimation(
            dx: targetPosition.x - currentPosition.x,
            dy: targetPosition.y - currentPosition.y
        )
    }

    private func arrive(at currentTime: TimeInterval) {
        currentPosition = targetPosition
        position = currentPosition
        zPosition = -position.y
        velocity = .zero
        isMoving = false
        currentAnimationDirection = nil
        stopWalking()
        nextTargetTime = currentTime + TimeInterval.random(in: 2.0...4.0)
    }

    private func updateAnimation(dx: CGFloat, dy: CGFloat) {
        let direction = VillagerWalkDirection(dx: dx, dy: dy)
        guard direction != currentAnimationDirection else { return }

        currentAnimationDirection = direction
        stopIdle()
        sprite.xScale = direction.isFlipped ? -abs(sprite.xScale) : abs(sprite.xScale)
        sprite.runAnimation(
            with: walkFrames.layeredFrames,
            row: direction.row,
            timePerFrame: 0.08,
            key: Self.walkActionKey
        )
    }

    private func stopWalking() {
        sprite.removeAnimation(forKey: Self.walkActionKey)
        sprite.xScale = abs(sprite.xScale)
        startIdle()
    }

    private func startIdle() {
        guard !sprite.hasAnimation(forKey: Self.idleActionKey) else { return }
        sprite.runAnimation(
            with: idleFrames.layeredFrames,
            row: 0,
            timePerFrame: 0.10,
            key: Self.idleActionKey
        )
    }

    private func stopIdle() {
        sprite.removeAnimation(forKey: Self.idleActionKey)
    }
}

private struct VillagerWalkDirection: Equatable {
    let row: Int
    let isFlipped: Bool

    init(dx: CGFloat, dy: CGFloat) {
        if abs(dx) > abs(dy) {
            row = 2
            isFlipped = dx > 0
        } else if dy > 0 {
            row = 4
            isFlipped = false
        } else {
            row = 0
            isFlipped = false
        }
    }
}

private struct VillagerWalkFrames {
    let layeredFrames: AvatarLayeredFrames

    init(hat: AvatarHat, scarf: AvatarScarf? = nil) {
        layeredFrames = AvatarLayeredAtlas.frames(
            kind: .walkRegular,
            hat: hat,
            scarf: scarf,
            filteringMode: .linear
        )
    }
}

private struct VillageSceneLayout {
    private static let tileSpacingScale: CGFloat = 0.88

    let size: CGSize
    let gridSize: Int
    let tileAnchorPoint: CGPoint

    var tileWidth: CGFloat {
        let horizontalTiles = 1 + CGFloat(gridSize - 1) * Self.tileSpacingScale
        let verticalTiles = 1 + CGFloat(gridSize - 1) * 0.5 * Self.tileSpacingScale
        let horizontalFit = size.width * 0.90 / horizontalTiles
        let verticalFit = size.height * 0.82 / verticalTiles
        return max(34, min(horizontalFit, verticalFit, 72))
    }

    var tileHeight: CGFloat {
        tileWidth * 0.5
    }

    var characterSize: CGFloat {
        min(tileWidth * 1.35, 86)
    }

    var characterSpeed: CGFloat {
        max(36, tileWidth * 0.9)
    }

    var characterYOffset: CGFloat {
        tileHeight * 0.15
    }

    func center(for tile: TileCoordinate) -> CGPoint {
        center(row: CGFloat(tile.row), column: CGFloat(tile.column))
    }

    private func center(row: CGFloat, column: CGFloat) -> CGPoint {
        let horizontalStep = tileWidth / 2 * Self.tileSpacingScale
        let verticalStep = tileHeight / 2 * Self.tileSpacingScale
        let boardHeight = CGFloat(gridSize - 1) * verticalStep * 2 + tileWidth
        let originX = size.width / 2
        let originY = (size.height + boardHeight) / 2 - tileWidth * (1 - tileAnchorPoint.y)
        let x = originX + (column - row) * horizontalStep
        let y = originY - (column + row) * verticalStep

        return CGPoint(x: x, y: y)
    }

    func characterPosition(for tile: TileCoordinate) -> CGPoint {
        characterPosition(row: CGFloat(tile.row), column: CGFloat(tile.column))
    }

    func randomCharacterPosition() -> CGPoint {
        characterPosition(
            row: CGFloat.random(in: 0...CGFloat(gridSize - 1)),
            column: CGFloat.random(in: 0...CGFloat(gridSize - 1))
        )
    }

    private func characterPosition(row: CGFloat, column: CGFloat) -> CGPoint {
        let center = center(row: row, column: column)
        return CGPoint(x: center.x, y: center.y + characterYOffset)
    }
}

private enum StableHash {
    static func value(for string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var result = state
        result = (result ^ (result >> 30)) &* 0xbf58476d1ce4e5b9
        result = (result ^ (result >> 27)) &* 0x94d049bb133111eb
        return result ^ (result >> 31)
    }
}

#if DEBUG
struct VillageViews_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VillagePage()
                .environmentObject(AuthSessionStore.preview(session: AuthSession.preview))
                .environmentObject(VillageStore.preview)
                .environmentObject(BerryStore.preview)
        }
    }
}
#endif
