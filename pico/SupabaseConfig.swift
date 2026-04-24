//
//  SupabaseConfig.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import Foundation

enum SupabaseConfig {
    static let projectURLString = "https://btaiubkusglnkyqgexef.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YWl1Ymt1c2dsbmt5cWdleGVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwNDczNDYsImV4cCI6MjA5MjYyMzM0Nn0.26r8v6t0RKX_6kiO-43kL5BtKVf2UkTpMs_rQ-emJlk"

    static var projectURL: URL? {
        URL(string: projectURLString)
    }

    static var isConfigured: Bool {
        projectURL != nil
            && !projectURLString.contains("your-project-ref")
            && !anonKey.contains("your-supabase-anon-key")
            && !anonKey.isEmpty
    }
}
