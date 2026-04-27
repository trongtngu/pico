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

    init(villageService: VillageService? = nil) {
        self.villageService = villageService ?? VillageService()
    }

    func loadResidents(for session: AuthSession?) async {
        guard let session, !isLoadingResidents else { return }

        loadState = .loading
        notice = nil

        do {
            residents = try await villageService.fetchResidents(for: session)
            hasLoadedResidents = true
            loadState = .loaded
        } catch {
            if error.isCancellation {
                loadState = hasLoadedResidents ? .loaded : .idle
                return
            }

            notice = displayMessage(for: error)
            loadState = .failed
        }
    }

    func clear() {
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
