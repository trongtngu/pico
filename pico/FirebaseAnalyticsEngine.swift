//
//  FirebaseAnalyticsEngine.swift
//  pico
//
//  Created by Codex on 17/5/2026.
//

import FirebaseAnalytics
import Foundation

struct FirebaseAnalyticsEngine: AnalyticsEngine {
    private let catalog: AnalyticsCatalog

    init(catalog: AnalyticsCatalog = .shared) {
        self.catalog = catalog
    }

    func track(_ event: AnalyticsEvent) {
        let parameters = mergedParameters(for: event)
        let validationErrors = validate(event: event, finalParameters: parameters)

        #if DEBUG
        if validationErrors.isEmpty {
            print("[Analytics] \(event.id.rawValue) \(debugParameters(parameters))")
        } else {
            validationErrors.forEach { print("[Analytics Warning] \($0)") }
        }
        #endif

        guard validationErrors.isEmpty else {
            return
        }

        FirebaseAnalytics.Analytics.logEvent(
            event.id.rawValue,
            parameters: firebaseParameters(parameters)
        )
    }

    func setUserId(_ userId: String?) {
        FirebaseAnalytics.Analytics.setUserID(userId)
    }

    func setUserProperty(_ value: String?, forName name: AnalyticsUserPropertyKey) {
        FirebaseAnalytics.Analytics.setUserProperty(value, forName: name.rawValue)
    }

    private func mergedParameters(for event: AnalyticsEvent) -> [AnalyticsParameterKey: AnalyticsValue] {
        var parameters = event.parameters
        parameters[.appVersion] = .string(appVersion)
        parameters[.buildNumber] = .string(buildNumber)
        parameters[.platform] = .string("ios")
        return parameters
    }

    private func validate(
        event: AnalyticsEvent,
        finalParameters: [AnalyticsParameterKey: AnalyticsValue]
    ) -> [String] {
        var errors: [String] = []

        guard let definition = catalog.definition(for: event.id) else {
            return ["Unregistered analytics event: \(event.id.rawValue)"]
        }

        validateFirebaseName(event.id.rawValue, kind: "Event name", limit: 40, errors: &errors)

        let sentParameterKeys = Set(event.parameters.keys)
        let missingParameters = definition.requiredParameters.subtracting(sentParameterKeys)
        if !missingParameters.isEmpty {
            errors.append(
                "Analytics event \(event.id.rawValue) is missing required parameters: \(names(missingParameters))"
            )
        }

        let allowedParameters = definition.requiredParameters
            .union(definition.optionalParameters)
            .union(AnalyticsCatalog.commonParameters)
        let unknownParameters = sentParameterKeys.subtracting(allowedParameters)
        if !unknownParameters.isEmpty {
            errors.append(
                "Analytics event \(event.id.rawValue) has unregistered parameters: \(names(unknownParameters))"
            )
        }

        if finalParameters.count > 25 {
            errors.append(
                "Analytics event \(event.id.rawValue) exceeds Firebase's 25 parameter limit after common parameters: \(finalParameters.count)"
            )
        }

        for key in finalParameters.keys {
            validateFirebaseName(key.rawValue, kind: "Parameter name", limit: 40, errors: &errors)
        }

        return errors
    }

    private func validateFirebaseName(
        _ name: String,
        kind: String,
        limit: Int,
        errors: inout [String]
    ) {
        if name.isEmpty {
            errors.append("\(kind) is empty.")
        }

        if name.count > limit {
            errors.append("\(kind) exceeds Firebase's \(limit) character limit: \(name)")
        }

        if name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) == nil {
            errors.append("\(kind) should be lowercase snake_case and start with a letter: \(name)")
        }

        if name.hasPrefix("firebase_") || name.hasPrefix("google_") || name.hasPrefix("ga_") {
            errors.append("\(kind) uses a reserved Firebase prefix: \(name)")
        }
    }

    private func firebaseParameters(
        _ parameters: [AnalyticsParameterKey: AnalyticsValue]
    ) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: parameters.map { key, value in
            (key.rawValue, firebaseValue(value))
        })
    }

    private func firebaseValue(_ value: AnalyticsValue) -> Any {
        switch value {
        case .string(let value):
            return value
        case .int(let value):
            return NSNumber(value: value)
        case .double(let value):
            return NSNumber(value: value)
        case .bool(let value):
            return NSNumber(value: value)
        }
    }

    #if DEBUG
    private func debugParameters(
        _ parameters: [AnalyticsParameterKey: AnalyticsValue]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: parameters.map { key, value in
            (key.rawValue, debugValue(value))
        })
    }

    private func debugValue(_ value: AnalyticsValue) -> String {
        switch value {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        }
    }
    #endif

    private func names(_ keys: Set<AnalyticsParameterKey>) -> String {
        keys.map(\.rawValue).sorted().joined(separator: ", ")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
