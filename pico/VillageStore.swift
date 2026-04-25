//
//  VillageStore.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Combine

@MainActor
final class VillageStore: ObservableObject {
    @Published private(set) var residents: [VillageResident] = []
    @Published private(set) var isLoadingResidents = false
    @Published var notice: String?

    private let villageService: VillageService

    init(villageService: VillageService? = nil) {
        self.villageService = villageService ?? VillageService()
    }

    func loadResidents(for session: AuthSession?) async {
        guard let session, !isLoadingResidents else { return }

        isLoadingResidents = true
        notice = nil
        defer { isLoadingResidents = false }

        do {
            residents = try await villageService.fetchResidents(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func clear() {
        residents = []
        notice = nil
        isLoadingResidents = false
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
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
