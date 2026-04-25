//
//  FocusViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SwiftUI
import Combine

struct FocusPage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore

    var body: some View {
        List {
            if let lobbySession = focusStore.lobbySession {
                FocusLobbyView(session: lobbySession)
            } else if let activeSession = focusStore.activeSession {
                ActiveFocusSessionView(session: activeSession)
            } else if let resultSession = focusStore.resultSession {
                FocusResultView(session: resultSession)
            } else {
                IncomingFocusInvitesView()
                CreateFocusLobbyView()
            }

            if let notice = focusStore.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: sessionStore.session?.user?.id) {
            await focusStore.restoreSavedState(for: sessionStore.session)
            await friendStore.loadFriends(for: sessionStore.session)
        }
        .refreshable {
            await focusStore.refresh(for: sessionStore.session)
            await friendStore.loadFriends(for: sessionStore.session)
        }
    }
}

private struct CreateFocusLobbyView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @State private var selectedMode = FocusSessionMode.solo

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Focus lobby", systemImage: selectedMode == .solo ? "timer" : "person.2")
                    .font(.headline)

                Text(selectedMode == .solo ? "Create a lobby, choose a duration, then start when ready." : "Create a lobby, invite friends, then start when ready.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Picker("Mode", selection: $selectedMode) {
                Text("Solo").tag(FocusSessionMode.solo)
                Text("Multiplayer").tag(FocusSessionMode.multiplayer)
            }
            .pickerStyle(.segmented)

            Button {
                Task {
                    await focusStore.createLobby(mode: selectedMode, for: sessionStore.session)
                }
            } label: {
                HStack {
                    Text("Create Lobby")
                    Spacer()
                    if focusStore.isCreating {
                        ProgressView()
                    }
                }
            }
            .disabled(focusStore.isCreating || focusStore.hasPendingResultSync)
        } header: {
            Text("Focus")
        }
    }
}

private struct IncomingFocusInvitesView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore

    var body: some View {
        if !focusStore.incomingInvites.isEmpty || focusStore.isLoadingInvites {
            Section {
                if focusStore.isLoadingInvites && focusStore.incomingInvites.isEmpty {
                    HStack {
                        Text("Loading invites")
                        Spacer()
                        ProgressView()
                    }
                }

                ForEach(focusStore.incomingInvites) { invite in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            AvatarBadgeView(config: invite.host.avatarConfig, size: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.host.displayName)
                                    .font(.headline)
                                Text("@\(invite.host.username) invited you")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(formattedDuration(invite.session.durationSeconds))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button {
                                Task {
                                    await focusStore.joinInvite(invite, for: sessionStore.session)
                                }
                            } label: {
                                HStack {
                                    Text("Accept")
                                    if focusStore.activeInviteID == invite.id {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(focusStore.activeInviteID != nil)

                            Button("Decline", role: .destructive) {
                                Task {
                                    await focusStore.declineInvite(invite, for: sessionStore.session)
                                }
                            }
                            .disabled(focusStore.activeInviteID != nil)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Invites")
            }
        }
    }
}

private struct FocusLobbyView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var focusStore: FocusStore
    @State private var durationMinutes: Int

    let session: FocusSession

    init(session: FocusSession) {
        self.session = session
        _durationMinutes = State(initialValue: max(1, session.durationSeconds / 60))
    }

    var body: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(session.mode == .solo ? "Solo lobby" : "Multiplayer lobby", systemImage: session.mode == .solo ? "timer" : "person.2")
                        .font(.headline)

                    Text(lobbySubtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if canManageLobby {
                    Stepper(value: $durationMinutes, in: 1...180, step: 5) {
                        LabeledContent("Duration", value: "\(durationMinutes) min")
                    }

                    Button {
                        Task {
                            await focusStore.updateLobbyDuration(durationMinutes * 60, for: sessionStore.session)
                        }
                    } label: {
                        HStack {
                            Text("Save Duration")
                            Spacer()
                            if focusStore.isUpdatingConfig {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!hasDurationChanges || focusStore.isUpdatingConfig)

                    Button {
                        Task {
                            await focusStore.startLobbySession(for: sessionStore.session)
                        }
                    } label: {
                        HStack {
                            Text("Start Focus")
                            Spacer()
                            if focusStore.isStarting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(focusStore.isStarting || focusStore.isUpdatingConfig)
                } else {
                    LabeledContent("Duration", value: "\(durationMinutes) min")
                }
            } header: {
                Text("Session Config")
            }

            if session.mode == .multiplayer {
                MultiplayerMembersSection(detail: focusStore.sessionDetail)
                InviteFriendsSection(
                    availableFriends: availableFriends,
                    canInvite: canManageLobby
                )
            }

            if canManageLobby {
                Section {
                    Button("Cancel Lobby", role: .destructive) {
                        Task {
                            await focusStore.cancelLobbySession(for: sessionStore.session)
                        }
                    }
                    .disabled(focusStore.isFinishing)
                }
            }
        }
        .onChange(of: session.id) {
            durationMinutes = max(1, session.durationSeconds / 60)
        }
        .onChange(of: session.durationSeconds) {
            durationMinutes = max(1, session.durationSeconds / 60)
        }
    }

    private var canManageLobby: Bool {
        focusStore.isCurrentUserHost(sessionStore.session)
    }

    private var hasDurationChanges: Bool {
        durationMinutes * 60 != session.durationSeconds
    }

    private var lobbySubtitle: String {
        if session.mode == .solo {
            return "Configure this solo session before starting. Once started, the duration is locked."
        }

        if canManageLobby {
            return "Invite friends before starting. Friends who joined by then participate."
        }

        return "Waiting for the host to start."
    }

    private var availableFriends: [UserProfile] {
        let memberIDs = Set(focusStore.sessionDetail?.members.map(\.userID) ?? [])
        return friendStore.friends.filter { !memberIDs.contains($0.userID) }
    }
}

private struct InviteFriendsSection: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore

    let availableFriends: [UserProfile]
    let canInvite: Bool

    var body: some View {
        if canInvite {
            Section {
                if availableFriends.isEmpty {
                    Text("No available friends to invite.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableFriends, id: \.userID) { friend in
                        Button {
                            Task {
                                await focusStore.inviteFriends([friend], for: sessionStore.session)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarBadgeView(config: friend.avatarConfig, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                    Text("@\(friend.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if focusStore.activeInvitedFriendIDs.contains(friend.userID) {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(focusStore.isInvitingMembers)
                    }
                }
            } header: {
                Text("Invite Friends")
            }
        }
    }
}

private struct MultiplayerMembersSection: View {
    let detail: FocusSessionDetail?

    var body: some View {
        Section {
            if let detail {
                ForEach(sortedMembers(detail.members)) { member in
                    FocusMemberRow(member: member)
                }
            } else {
                HStack {
                    Text("Loading members")
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text("Members")
        }
    }

    private func sortedMembers(_ members: [FocusSessionMember]) -> [FocusSessionMember] {
        members.sorted {
            if $0.role != $1.role {
                return $0.role == .host
            }
            return $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName) == .orderedAscending
        }
    }
}

private struct FocusMemberRow: View {
    let member: FocusSessionMember

    var body: some View {
        HStack(spacing: 12) {
            AvatarBadgeView(config: member.profile.avatarConfig, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.profile.displayName)
                    if member.role == .host {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text("@\(member.profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(memberStatusText(member))
                .font(.subheadline)
                .foregroundStyle(memberStatusColor(member))
        }
        .padding(.vertical, 2)
    }
}

private struct ActiveFocusSessionView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore
    @State private var now = Date()

    let session: FocusSession
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(session.mode == .solo ? "Focus in progress" : "Multiplayer focus", systemImage: session.mode == .solo ? "timer" : "person.2")
                        .font(.headline)

                    Text(formattedDuration(session.remainingSeconds(at: now)))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    ProgressView(value: progress)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Active Session")
            } footer: {
                Text("Locking your phone is allowed. Leaving the app interrupts your session.")
            }

            Section {
                LabeledContent("Started", value: session.startedAt?.formatted(date: .omitted, time: .shortened) ?? "--")
                LabeledContent("Ends", value: session.plannedEndAt?.formatted(date: .omitted, time: .shortened) ?? "--")

                Button("End Session", role: .destructive) {
                    Task {
                        await focusStore.interruptCurrentSession(for: sessionStore.session)
                    }
                }
                .disabled(focusStore.isFinishing)
            }

            if session.mode == .multiplayer {
                MultiplayerMembersSection(detail: focusStore.sessionDetail)
            }
        }
        .onReceive(timer) { date in
            now = date
            guard session.remainingSeconds(at: date) == 0, !focusStore.isFinishing else { return }
            Task {
                await focusStore.completeCurrentSession(for: sessionStore.session)
            }
        }
    }

    private var progress: Double {
        let elapsed = Double(session.elapsedSeconds(at: now))
        return min(1, max(0, elapsed / Double(session.durationSeconds)))
    }
}

private struct FocusResultView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var focusStore: FocusStore

    let session: FocusSession

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)

                Text(subtitle)
                    .foregroundStyle(.secondary)

                LabeledContent("Duration", value: formattedDuration(session.elapsedSeconds()))
            }
            .padding(.vertical, 6)
        } header: {
            Text("Result")
        }

        Section {
            if focusStore.hasPendingResultSync {
                Button {
                    Task {
                        await focusStore.retryPendingResult(for: sessionStore.session)
                    }
                } label: {
                    HStack {
                        Text("Retry Saving Result")
                        Spacer()
                        if focusStore.isFinishing {
                            ProgressView()
                        }
                    }
                }
                .disabled(focusStore.isFinishing)
            } else {
                Button("Start Another Session") {
                    focusStore.resetResult()
                }
            }
        }
    }

    private var title: String {
        switch session.status {
        case .lobby:
            "Session Lobby"
        case .live:
            "Session Live"
        case .completed:
            "Session Completed"
        case .interrupted:
            "Session Interrupted"
        case .cancelled:
            "Session Cancelled"
        }
    }

    private var subtitle: String {
        switch session.status {
        case .lobby:
            "This session has not started."
        case .live:
            "This session is still running."
        case .completed:
            "The full focus window was completed."
        case .interrupted:
            "The focus window ended before the timer finished."
        case .cancelled:
            "The lobby or session was cancelled."
        }
    }

    private var icon: String {
        switch session.status {
        case .lobby:
            "person.crop.circle.badge.clock"
        case .live:
            "timer"
        case .completed:
            "checkmark.circle"
        case .interrupted:
            "xmark.circle"
        case .cancelled:
            "minus.circle"
        }
    }
}

private func memberStatusText(_ member: FocusSessionMember) -> String {
    if member.isInterrupted {
        return "Interrupted"
    }

    if member.isCompleted {
        return "Complete"
    }

    switch member.status {
    case .invited:
        return "Invited"
    case .joined:
        return "Joined"
    case .left:
        return "Left"
    }
}

private func memberStatusColor(_ member: FocusSessionMember) -> Color {
    if member.isInterrupted || member.status == .left {
        return .secondary
    }

    if member.isCompleted {
        return .green
    }

    if member.status == .joined {
        return .blue
    }

    return .secondary
}

private func formattedDuration(_ seconds: Int) -> String {
    let clampedSeconds = max(0, seconds)
    let minutes = clampedSeconds / 60
    let seconds = clampedSeconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
}

#if DEBUG
struct FocusViews_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FocusPage()
                .environmentObject(AuthSessionStore.preview(session: AuthSession.preview))
                .environmentObject(FriendStore.preview)
                .environmentObject(FocusStore.preview)
        }
    }
}
#endif
