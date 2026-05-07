//
//  DailySnapshotStore.swift
//  pico
//
//  Created by Codex on 7/5/2026.
//

import Foundation
import Combine

enum DailySnapshotLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
final class DailySnapshotStore: ObservableObject {
    @Published private(set) var selectedDay = DailySnapshotDay()
    @Published private(set) var currentSnapshot: DailyVillageSnapshot?
    @Published private(set) var availableSnapshots: [DailyVillageSnapshot] = []
    @Published private(set) var loadState: DailySnapshotLoadState = .idle
    @Published private(set) var rangeLoadState: DailySnapshotLoadState = .idle
    @Published var notice: String?

    var availableDays: [DailySnapshotDay] {
        availableSnapshots.map(\.snapshotDay)
    }

    var isLoadingSnapshot: Bool {
        loadState == .loading
    }

    var isLoadingRange: Bool {
        rangeLoadState == .loading
    }

    private let dailySnapshotService: DailySnapshotService
    private var snapshotLoadGeneration = 0
    private var rangeLoadGeneration = 0

    init(dailySnapshotService: DailySnapshotService? = nil) {
        self.dailySnapshotService = dailySnapshotService ?? DailySnapshotService()
    }

    func loadToday(for session: AuthSession?) async {
        let today = DailySnapshotDay(date: Date(), calendar: .current)
        await loadSnapshot(day: today, for: session)
    }

    func loadSnapshot(day: DailySnapshotDay, for session: AuthSession?) async {
        selectedDay = day
        guard let session else {
            currentSnapshot = nil
            loadState = .idle
            notice = nil
            return
        }

        snapshotLoadGeneration += 1
        let generation = snapshotLoadGeneration
        loadState = .loading
        notice = nil
        currentSnapshot = nil

        do {
            let snapshot = try await dailySnapshotService.fetchSnapshot(day: day, for: session)
            guard generation == snapshotLoadGeneration else { return }

            selectedDay = snapshot?.snapshotDay ?? day
            currentSnapshot = snapshot
            notice = snapshot?.notice
            loadState = .loaded
        } catch {
            guard generation == snapshotLoadGeneration else { return }

            if error.isCancellation {
                loadState = currentSnapshot == nil ? .idle : .loaded
                return
            }

            notice = displayMessage(for: error)
            currentSnapshot = nil
            loadState = .failed
        }
    }

    func loadSnapshotRange(
        startDay: DailySnapshotDay,
        endDay: DailySnapshotDay,
        for session: AuthSession?
    ) async {
        guard let session else { return }
        guard !isLoadingRange else { return }

        rangeLoadGeneration += 1
        let generation = rangeLoadGeneration
        rangeLoadState = .loading
        notice = nil

        do {
            let snapshots = try await dailySnapshotService.listSnapshots(
                startDay: startDay,
                endDay: endDay,
                for: session
            )
            guard generation == rangeLoadGeneration else { return }

            availableSnapshots = snapshots
            rangeLoadState = .loaded
        } catch {
            guard generation == rangeLoadGeneration else { return }

            if error.isCancellation {
                rangeLoadState = availableSnapshots.isEmpty ? .idle : .loaded
                return
            }

            notice = displayMessage(for: error)
            rangeLoadState = .failed
        }
    }

    func clear() {
        snapshotLoadGeneration += 1
        rangeLoadGeneration += 1
        selectedDay = DailySnapshotDay(date: Date(), calendar: .current)
        currentSnapshot = nil
        availableSnapshots = []
        loadState = .idle
        rangeLoadState = .idle
        notice = nil
    }

    #if DEBUG
    static var preview: DailySnapshotStore {
        let store = DailySnapshotStore()
        let owner = UserProfile(
            userID: AuthUser.preview.id,
            username: "tommy",
            displayName: "Tommy",
            avatarConfig: AvatarCatalog.defaultConfig
        )
        let visitor = DailyVillageSnapshotVisitor(
            profile: UserProfile(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
                username: "casey",
                displayName: "Casey",
                avatarConfig: AvatarConfig(key: "avatar_2")
            ),
            bondLevel: 2,
            completedPairSessions: 4
        )
        let snapshot = DailyVillageSnapshot(
            ownerID: owner.userID,
            snapshotDay: DailySnapshotDay(rawValue: "2026-05-07"),
            userTimezone: "Australia/Sydney",
            islandID: PicoIsland.original.backendID,
            ownerProfile: owner,
            visitors: [visitor],
            focusSessionIDs: [],
            createdAt: Date(),
            updatedAt: Date(),
            notice: nil
        )
        store.selectedDay = snapshot.snapshotDay
        store.currentSnapshot = snapshot
        store.availableSnapshots = [snapshot]
        store.loadState = .loaded
        store.rangeLoadState = .loaded
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
