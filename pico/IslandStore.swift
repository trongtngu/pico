//
//  IslandStore.swift
//  pico
//
//  Created by Codex on 2/5/2026.
//

import Foundation
import Combine

enum PicoIsland: String, CaseIterable, Identifiable, Codable {
    case original
    case sand

    nonisolated var id: String { rawValue }

    nonisolated var backendID: String {
        switch self {
        case .original:
            "default"
        case .sand:
            "sand"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .original:
            "Forest island"
        case .sand:
            "Beach Island"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .original:
            "Classic fishing waters shaded by the trees."
        case .sand:
            "A warmer shore with its own catch list."
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .original:
            "leaf.fill"
        case .sand:
            "sun.max.fill"
        }
    }

    nonisolated init(backendID: String?) {
        switch backendID?.lowercased() {
        case "sand":
            self = .sand
        default:
            self = .original
        }
    }

    var mapStyle: VillageMapStyle {
        switch self {
        case .original:
            .originalIsland
        case .sand:
            .sandIsland
        }
    }

    init(mapStyle: VillageMapStyle) {
        switch mapStyle {
        case .originalIsland:
            self = .original
        case .sandIsland:
            self = .sand
        }
    }
}

@MainActor
final class IslandStore: ObservableObject {
    @Published var selectedIsland: PicoIsland = .original

    private let userDefaults: UserDefaults
    private let keyPrefix = "pico.selected-island"
    private var currentUserID: UUID?
    private var ownedIslandIDs: Set<String> = [PicoIsland.original.backendID]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var selectedIslandID: String {
        selectedIsland.backendID
    }

    func configure(for userID: UUID?, ownedIslandIDs: Set<String> = [PicoIsland.original.backendID]) {
        self.ownedIslandIDs = ownedIslandIDs.union([PicoIsland.original.backendID])
        guard currentUserID != userID else { return }

        currentUserID = userID
        guard let userID else {
            selectedIsland = .original
            return
        }

        let storedIsland = PicoIsland(backendID: userDefaults.string(forKey: storageKey(for: userID)))
        let ownedStoredIsland = isOwned(storedIsland) ? storedIsland : .original
        selectedIsland = ownedStoredIsland
        persistSelectedIsland()
    }

    func select(_ island: PicoIsland) {
        guard isOwned(island) else { return }
        guard selectedIsland != island else { return }
        selectedIsland = island
        persistSelectedIsland()
    }

    func select(mapStyle: VillageMapStyle) {
        select(PicoIsland(mapStyle: mapStyle))
    }

    func updateOwnedIslandIDs(_ ownedIslandIDs: Set<String>) {
        self.ownedIslandIDs = ownedIslandIDs.union([PicoIsland.original.backendID])
        if !isOwned(selectedIsland) {
            selectedIsland = .original
            persistSelectedIsland()
        }
    }

    func isOwned(_ island: PicoIsland) -> Bool {
        island == .original || ownedIslandIDs.contains(island.backendID)
    }

    private func persistSelectedIsland() {
        if let currentUserID {
            userDefaults.set(selectedIsland.backendID, forKey: storageKey(for: currentUserID))
        }
    }

    private func storageKey(for userID: UUID) -> String {
        "\(keyPrefix).\(userID.uuidString)"
    }
}
