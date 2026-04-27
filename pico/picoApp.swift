//
//  picoApp.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

import SwiftUI

@main
struct picoApp: App {
    init() {
        #if canImport(UIKit)
        PicoSegmentedControlAppearance.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
