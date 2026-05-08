//
//  AnalyticsEvent.swift
//  pico
//
//  Created by Codex on 9/5/2026.
//

import Foundation

struct AnalyticsEvent {
    let name: String
    let parameters: [String: Any]?

    init(name: String, parameters: [String: Any]? = nil) {
        self.name = name
        self.parameters = parameters

        validate()
    }

    #if DEBUG
    private func validate() {
        if name.isEmpty {
            print("[Analytics Warning] Event name is empty.")
        }

        if name.count > 40 {
            print("[Analytics Warning] Event name exceeds Firebase's 40 character limit: \(name)")
        }

        if name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) == nil {
            print("[Analytics Warning] Event name should be lowercase snake_case and start with a letter: \(name)")
        }

        if name.hasPrefix("firebase_") || name.hasPrefix("google_") || name.hasPrefix("ga_") {
            print("[Analytics Warning] Event name uses a reserved Firebase prefix: \(name)")
        }

        if let parameters, parameters.count > 25 {
            print("[Analytics Warning] Event has more than 25 parameters: \(name)")
        }
    }
    #else
    private func validate() {}
    #endif
}
