//
//  ScoreStore.swift
//  pico
//
//  Created by Codex on 26/4/2026.
//

import Foundation
import Combine

@MainActor
final class ScoreStore: ObservableObject {
    @Published private(set) var score: UserScore = .zero
    @Published private(set) var isLoadingScore = false
    @Published var notice: String?

    var currentStreak: Int {
        score.currentStreak
    }

    private let scoreService: ScoreService

    init(scoreService: ScoreService? = nil) {
        self.scoreService = scoreService ?? ScoreService()
    }

    func loadScore(for session: AuthSession?) async {
        guard let session, !isLoadingScore else { return }

        isLoadingScore = true
        notice = nil
        defer { isLoadingScore = false }

        do {
            score = try await scoreService.fetchUserScore(for: session)
        } catch {
            notice = displayMessage(for: error)
        }
    }

    func applyScore(_ score: UserScore) {
        self.score = score
        notice = nil
    }

    func clear() {
        score = .zero
        notice = nil
        isLoadingScore = false
    }

    #if DEBUG
    static var preview: ScoreStore {
        let store = ScoreStore()
        store.score = UserScore(
            score: 12,
            currentStreak: 4,
            lastScoredOn: nil,
            lastScoredAt: nil
        )
        return store
    }
    #endif

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
