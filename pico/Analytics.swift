//
//  Analytics.swift
//  pico
//
//  Created by Codex on 17/5/2026.
//

import Foundation

enum Analytics {
    private static let engine: AnalyticsEngine = FirebaseAnalyticsEngine()

    static func track(_ event: AnalyticsEvent) {
        engine.track(event)
    }

    static func setUserId(_ userId: String?) {
        engine.setUserId(userId)
    }

    static func setUserProperty(_ value: String?, forName name: AnalyticsUserPropertyKey) {
        engine.setUserProperty(value, forName: name)
    }
}
