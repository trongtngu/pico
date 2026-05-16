//
//  PicoPlusEntitlements.swift
//  pico
//
//  Created by Codex on 15/5/2026.
//

import Foundation

enum PicoPlusPlacement: String {
    case onboardingComplete = "onboarding_complete"
    case largeGroupSession = "pico_plus_large_group_session"
    case exclusiveHat = "pico_plus_exclusive_hat"
    case calendarView = "pico_plus_calendar_view"
    case bondReward = "pico_plus_bond_scarf"
}

enum PicoPlusPaywallSource: Equatable {
    case onboardingComplete(placement: PicoPlusPlacement)
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
        case .onboardingComplete(let placement),
             .calendarView(let placement),
             .bondReward(_, _, let placement),
             .largeGroupSession(_, _, _, let placement),
             .plusCosmetic(_, _, _, let placement):
            placement
        }
    }

    var analyticsValue: String {
        switch self {
        case .onboardingComplete:
            "onboarding_complete"
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
    let freeMultiplayerMemberLimit: Int
    let freeBondRewardLevel: Int
    let fishSaleBerryMultiplier: Int

    static let free = PicoPlusCapabilities(
        isPlusActive: false,
        multiplayerMemberLimit: PicoPlusEntitlements.freeMultiplayerMemberLimit,
        freeMultiplayerMemberLimit: PicoPlusEntitlements.freeMultiplayerMemberLimit,
        freeBondRewardLevel: PicoPlusEntitlements.freeBondRewardLevel,
        fishSaleBerryMultiplier: 1
    )

    static let plus = PicoPlusCapabilities(
        isPlusActive: true,
        multiplayerMemberLimit: nil,
        freeMultiplayerMemberLimit: PicoPlusEntitlements.freeMultiplayerMemberLimit,
        freeBondRewardLevel: PicoPlusEntitlements.freeBondRewardLevel,
        fishSaleBerryMultiplier: PicoPlusEntitlements.plusFishSaleBerryMultiplier
    )

    var canAccessHistoricalDailySnapshots: Bool {
        isPlusActive
    }

    var canClaimAllBondRewards: Bool {
        isPlusActive
    }

    var canPurchasePaidOnlyStoreItems: Bool {
        isPlusActive
    }

    func canAccessDailySnapshot(isPastDay: Bool) -> Bool {
        !isPastDay || canAccessHistoricalDailySnapshots
    }

    func bondRewardRequiresPlus(level: Int) -> Bool {
        !canClaimBondReward(level: level)
    }

    func canClaimBondReward(level: Int) -> Bool {
        canClaimAllBondRewards || level <= freeBondRewardLevel
    }

    func visibleBondRewardLevel(earnedLevel: Int, claimedLevel: Int) -> Int {
        let cappedClaimedLevel = canClaimAllBondRewards
            ? claimedLevel
            : min(claimedLevel, freeBondRewardLevel)
        return min(max(0, earnedLevel), max(0, cappedClaimedLevel))
    }

    func canPurchaseStoreItem(_ item: StoreItem) -> Bool {
        !item.isPaidOnly || canPurchasePaidOnlyStoreItems
    }

    func remainingMultiplayerInviteSlots(currentMemberCount: Int) -> Int {
        guard let multiplayerMemberLimit else { return Int.max }
        return max(0, multiplayerMemberLimit - currentMemberCount)
    }

    func selectedInvitesReachMultiplayerLimit(currentMemberCount: Int, selectedInviteCount: Int) -> Bool {
        guard multiplayerMemberLimit != nil else { return false }
        return selectedInviteCount >= remainingMultiplayerInviteSlots(currentMemberCount: currentMemberCount)
    }
}

enum PicoPlusEntitlements {
    static let freeMultiplayerMemberLimit = 4
    static let freeBondRewardLevel = 2
    static let plusFishSaleBerryMultiplier = 3

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
