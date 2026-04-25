//
//  VillageViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SwiftUI

struct VillagePage: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @EnvironmentObject private var villageStore: VillageStore

    var body: some View {
        List {
            Section {
                if villageStore.isLoadingResidents {
                    HStack {
                        Text("Loading village")
                        Spacer()
                        ProgressView()
                    }
                } else if villageStore.residents.isEmpty {
                    ContentUnavailableView {
                        Label("No residents yet", systemImage: "house")
                    } description: {
                        Text("Complete a multiplayer focus session with someone to welcome them here.")
                    }
                } else {
                    ForEach(villageStore.residents) { resident in
                        ResidentCardView(resident: resident)
                    }
                }
            } header: {
                Text("Residents")
            }

            if let notice = villageStore.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(.secondary)
                }
            }
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

struct ResidentCardView: View {
    let resident: VillageResident

    var body: some View {
        HStack(spacing: 12) {
            AvatarBadgeView(config: resident.profile.avatarConfig, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(resident.profile.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text("@\(resident.profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Label("Level \(resident.bondLevel)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)

                Text(sessionCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var sessionCountText: String {
        if resident.completedPairSessions == 1 {
            return "1 session"
        }

        return "\(resident.completedPairSessions) sessions"
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
