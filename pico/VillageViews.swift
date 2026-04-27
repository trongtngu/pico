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

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                VillageView(
                    residents: villageStore.residents,
                    currentUserProfile: sessionStore.profile
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
                        .foregroundStyle(.secondary)
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

    private static let gridSize = 6
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
        gridResidents
            .map { "\($0.id.uuidString)-\($0.profile.avatarConfig.selectedHat.rawValue)" }
            .joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: VillageScene(
                    size: proxy.size,
                    gridSize: Self.gridSize,
                    residents: gridResidents
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
    private var renderedSize: CGSize = .zero
    private var villagers: [VillagerNode] = []
    private var lastUpdateTime: TimeInterval?

    init(size: CGSize, gridSize: Int, residents: [VillageResident]) {
        self.gridSize = gridSize
        self.residents = Array(residents.prefix(gridSize * gridSize))
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
        drawVillagers()
    }

    private func drawGrid() {
        let layout = VillageSceneLayout(
            size: size,
            gridSize: gridSize,
            tileAnchorPoint: Self.tileAnchorPoint
        )
        let atlas = SKTextureAtlas(named: "grass_tiles")
        let grassBlockTexture = atlas.textureNamed("dirt_with_grass.png")
        grassBlockTexture.filteringMode = .linear

        for tile in TileCoordinate.all(in: gridSize) {
            addTileSprite(texture: grassBlockTexture, tile: tile, layout: layout)
        }
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
            let idleFrames = AvatarIdleFrames(hat: selectedHat)
            let walkFrames = VillagerWalkFrames(hat: selectedHat)
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

private final class VillagerNode: SKNode {
    private static let walkActionKey = "walk"
    private static let idleActionKey = "idle"

    private let sprite: SKSpriteNode
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
        self.sprite = SKSpriteNode(texture: idleFrames.firstFrame())
        self.movementSpeed = speed
        super.init()

        position = currentPosition
        zPosition = -currentPosition.y
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.12)
        sprite.size = CGSize(width: characterSize, height: characterSize)
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
        sprite.run(
            .repeatForever(.animate(with: walkFrames.frames(forRow: direction.row), timePerFrame: 0.08)),
            withKey: Self.walkActionKey
        )
    }

    private func stopWalking() {
        sprite.removeAction(forKey: Self.walkActionKey)
        sprite.xScale = abs(sprite.xScale)
        startIdle()
    }

    private func startIdle() {
        guard sprite.action(forKey: Self.idleActionKey) == nil else { return }
        sprite.run(
            .repeatForever(.animate(with: idleFrames.frames(forRow: 0), timePerFrame: 0.10)),
            withKey: Self.idleActionKey
        )
    }

    private func stopIdle() {
        sprite.removeAction(forKey: Self.idleActionKey)
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
    private static let atlasImageName = "CharacterWalk_Set1.1"
    private static let atlasPixelSize = CGSize(width: 1388, height: 1737)
    private static let sheetPixelSize = CGSize(width: 690, height: 575)
    private static let atlasInset: CGFloat = 2
    private static let sheetSpacing: CGFloat = 4
    private static let rowCount = 5
    private static let frameCount = 6

    private let frames: [[SKTexture]]

    init(hat: AvatarHat) {
        let atlasTexture = SKTexture(imageNamed: Self.atlasImageName)
        atlasTexture.filteringMode = .linear

        frames = (0..<Self.rowCount).map { row in
            (0..<Self.frameCount).map { frame in
                let texture = SKTexture(rect: Self.normalizedFrameRect(hat: hat, row: row, frame: frame), in: atlasTexture)
                texture.filteringMode = .linear
                return texture
            }
        }
    }

    func frames(forRow row: Int) -> [SKTexture] {
        frames[min(max(row, 0), Self.rowCount - 1)]
    }

    private static func normalizedFrameRect(hat: AvatarHat, row: Int, frame: Int) -> CGRect {
        let slot = hat.walkAtlasSlot
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

#if DEBUG
struct VillageViews_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VillagePage()
                .environmentObject(AuthSessionStore.preview(session: AuthSession.preview))
                .environmentObject(VillageStore.preview)
        }
    }
}
#endif
