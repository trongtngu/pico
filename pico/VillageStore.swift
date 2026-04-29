//
//  VillageStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

enum VillageLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
final class VillageStore: ObservableObject {
    @Published private(set) var residents: [VillageResident] = []
    @Published private(set) var loadState: VillageLoadState = .idle
    @Published private(set) var hasLoadedResidents = false
    @Published var notice: String?

    var isLoadingResidents: Bool {
        loadState == .loading
    }

    private let villageService: VillageService
    private var loadGeneration = 0

    init(villageService: VillageService? = nil) {
        self.villageService = villageService ?? VillageService()
    }

    func loadResidents(for session: AuthSession?, force: Bool = false) async {
        guard let session else { return }
        guard force || !isLoadingResidents else { return }

        loadGeneration += 1
        let generation = loadGeneration
        loadState = .loading
        notice = nil

        do {
            let fetchedResidents = try await villageService.fetchResidents(for: session)
            guard generation == loadGeneration else { return }

            residents = fetchedResidents
            hasLoadedResidents = true
            loadState = .loaded
        } catch {
            guard generation == loadGeneration else { return }

            if error.isCancellation {
                loadState = hasLoadedResidents ? .loaded : .idle
                return
            }

            notice = displayMessage(for: error)
            loadState = .failed
        }
    }

    func clear() {
        loadGeneration += 1
        residents = []
        notice = nil
        loadState = .idle
        hasLoadedResidents = false
    }

    func scarf(for userID: UUID) -> AvatarScarf? {
        guard let resident = residents.first(where: { $0.profile.userID == userID }) else {
            return nil
        }

        return AvatarScarf(bondLevel: resident.bondLevel)
    }

    #if DEBUG
    static var preview: VillageStore {
        let store = VillageStore()
        store.residents = [
            VillageResident(
                profile: UserProfile(
                    userID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
                    username: "casey",
                    displayName: "Casey",
                    avatarConfig: AvatarConfig(key: "avatar_2")
                ),
                bondLevel: 2,
                completedPairSessions: 4,
                unlockedAt: Date()
            )
        ]
        store.loadState = .loaded
        store.hasLoadedResidents = true
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

@MainActor
final class BondRewardClaimStore: ObservableObject {
    @Published private var claimedLevels: [String: Int] = [:]

    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        fileURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("bond-reward-claims.json")

        load()
    }

    func claimedLevel(ownerID: UUID?, residentID: UUID) -> Int {
        guard let ownerID else { return 0 }
        return claimedLevels[key(ownerID: ownerID, residentID: residentID)] ?? 0
    }

    func markClaimed(level: Int, ownerID: UUID?, residentID: UUID) {
        guard let ownerID else { return }

        let claimKey = key(ownerID: ownerID, residentID: residentID)
        guard level > (claimedLevels[claimKey] ?? 0) else { return }

        claimedLevels[claimKey] = level
        save()
    }

    private func key(ownerID: UUID, residentID: UUID) -> String {
        "\(ownerID.uuidString):\(residentID.uuidString)"
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        claimedLevels = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(claimedLevels) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
