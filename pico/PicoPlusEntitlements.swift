//
//  PicoPlusEntitlements.swift
//  pico
//
//  Created by Codex on 15/5/2026.
//

import Foundation

enum PicoPlusPlacement: String {
    case largeGroupSession = "pico_plus_large_group_session"
    case exclusiveHat = "pico_plus_exclusive_hat"
    case calendarView = "pico_plus_calendar_view"
    case bondReward = "pico_plus_bond_scarf"
}

enum PicoPlusPaywallSource: Equatable {
    case calendarView(placement: PicoPlusPlacement)
    case bondReward(
        residentID: String,
        bondLevel: Int,
        placement: PicoPlusPlacement
    )
    case largeGroupSession(
        currentMembers: Int,
        selectedInvites: Int,
        limit: Int,
        placement: PicoPlusPlacement
    )
    case plusCosmetic(
        itemID: String,
        itemType: String,
        itemKey: String,
        placement: PicoPlusPlacement
    )

    var placement: PicoPlusPlacement {
        switch self {
        case .calendarView(let placement),
             .bondReward(_, _, let placement),
             .largeGroupSession(_, _, _, let placement),
             .plusCosmetic(_, _, _, let placement):
            placement
        }
    }

    var analyticsValue: String {
        switch self {
        case .calendarView:
            "calendar_view"
        case .bondReward:
            "bond_reward"
        case .largeGroupSession:
            "large_group_session"
        case .plusCosmetic:
            "plus_cosmetic"
        }
    }
}

struct PicoPlusCapabilities: Equatable {
    let isPlusActive: Bool
    let multiplayerMemberLimit: Int?

    static let free = PicoPlusCapabilities(
        isPlusActive: false,
        multiplayerMemberLimit: PicoPlusEntitlements.freeMultiplayerMemberLimit
    )

    static let plus = PicoPlusCapabilities(
        isPlusActive: true,
        multiplayerMemberLimit: nil
    )
}

enum PicoPlusEntitlements {
    static let freeMultiplayerMemberLimit = 4
    static let freeBondRewardLevel = 2
    static let fishSaleBerryMultiplier = 3

    static func capabilities(isPlusActive: Bool) -> PicoPlusCapabilities {
        isPlusActive ? .plus : .free
    }
}

struct PicoPlusEntitlement: Equatable {
    let isActive: Bool
    let status: String?
    let provider: String?
    let currentPeriodEnd: Date?

    static let free = PicoPlusEntitlement(
        isActive: false,
        status: nil,
        provider: nil,
        currentPeriodEnd: nil
    )
}
