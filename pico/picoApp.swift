//
//  picoApp.swift
//  pico
//
//  Created by Tommy Nguyen on 25/4/2026.
//

import FirebaseCore
import SwiftUI

@main
struct picoApp: App {
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        GoogleSignInClient.configure()
        PicoPlusService.configurePaywallProvider()

        #if canImport(UIKit)
        PicoSegmentedControlAppearance.configure()
        PicoNavigationBarAppearance.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = GoogleSignInClient.handleOpenURL(url)
                }
        }
    }
}
