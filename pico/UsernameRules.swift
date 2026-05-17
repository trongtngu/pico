//
//  UsernameRules.swift
//  pico
//
//  Created by Codex on 16/5/2026.
//

import Foundation

enum PicoUsernameRules {
    static func isValidUserChosenUsername(_ username: String) -> Bool {
        username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil
            && !isGeneratedOAuthUsername(username)
    }

    static func isGeneratedOAuthUsername(_ username: String) -> Bool {
        username.range(of: "^pico_[0-9a-f]{19}$", options: .regularExpression) != nil
    }
}
