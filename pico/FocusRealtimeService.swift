//
//  FocusRealtimeService.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation
import Supabase

final class FocusRealtimeSubscription {
    private let client: SupabaseClient
    private let onChange: @Sendable () -> Void
    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []
    private var subscribeTask: Task<Void, Never>?

    init?(accessToken: String, onChange: @escaping @Sendable () -> Void) {
        guard SupabaseConfig.isConfigured, let projectURL = SupabaseConfig.projectURL else {
            return nil
        }

        self.onChange = onChange
        self.client = SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(accessToken: { accessToken })
            )
        )
    }

    deinit {
        stop()
    }

    func start(channelID: String, sessionID: UUID?, userID: UUID) {
        stop()

        let channel = client.channel(channelID)
        self.channel = channel

        if let sessionID {
            streamTasks = [
                makeRefreshTask(channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "focus_sessions",
                    filter: .eq("id", value: sessionID)
                )),
                makeRefreshTask(channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "session_members",
                    filter: .eq("session_id", value: sessionID)
                )),
                makeRefreshTask(channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "session_events",
                    filter: .eq("session_id", value: sessionID)
                ))
            ]
        } else {
            streamTasks = [
                makeRefreshTask(channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "session_members",
                    filter: .eq("user_id", value: userID)
                ))
            ]
        }

        subscribeTask = Task {
            try? await channel.subscribeWithError()
        }
    }

    func stop() {
        subscribeTask?.cancel()
        subscribeTask = nil
        streamTasks.forEach { $0.cancel() }
        streamTasks = []

        guard let channel else { return }
        self.channel = nil
        Task {
            await client.removeChannel(channel)
        }
    }

    private func makeRefreshTask<Action>(
        _ stream: AsyncStream<Action>
    ) -> Task<Void, Never> {
        Task { [onChange] in
            for await _ in stream {
                guard !Task.isCancelled else { return }
                onChange()
            }
        }
    }
}
