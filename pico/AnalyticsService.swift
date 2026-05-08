//
//  AnalyticsService.swift
//  pico
//
//  Created by Codex on 9/5/2026.
//

import FirebaseAnalytics
import Foundation

enum AnalyticsService {
    static func track(_ event: AnalyticsEvent) {
        let parameters = mergedParameters(for: event)

        #if DEBUG
        if parameters.count > 25 {
            print("[Analytics Warning] Event exceeds Firebase's 25 parameter limit after common parameters: \(event.name)")
        }
        print("[Analytics] \(event.name) \(parameters)")
        #endif

        Analytics.logEvent(event.name, parameters: parameters)
    }

    static func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
    }

    static func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    private static func mergedParameters(for event: AnalyticsEvent) -> [String: Any] {
        var parameters = event.parameters ?? [:]
        parameters["app_version"] = appVersion
        parameters["build_number"] = buildNumber
        parameters["platform"] = "ios"
        return parameters
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
