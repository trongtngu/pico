//
//  GoogleSignInClient.swift
//  pico
//
//  Created by Codex on 13/5/2026.
//

import Foundation
import CryptoKit
import GoogleSignIn
import Security
#if canImport(UIKit)
import UIKit
#endif

struct GoogleSignInTokens {
    let idToken: String
    let accessToken: String?
    let nonce: String
    let displayName: String?
}

enum GoogleSignInClientError: LocalizedError {
    case missingClientID
    case missingPresenter
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Google Sign-In is missing its client ID."
        case .missingPresenter:
            "Google Sign-In could not find a view to present from."
        case .missingIDToken:
            "Google did not return a valid identity token."
        }
    }
}

@MainActor
enum GoogleSignInClient {
    static func configure() {
        guard let clientID = GoogleSignInConfig.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    static func signIn() async throws -> GoogleSignInTokens {
        guard GoogleSignInConfig.clientID != nil else {
            throw GoogleSignInClientError.missingClientID
        }

        configure()

        #if canImport(UIKit)
        guard let presenter = UIApplication.shared.picoTopViewController else {
            throw GoogleSignInClientError.missingPresenter
        }

        let nonce = GoogleSignInNonce.random()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: nil,
            nonce: GoogleSignInNonce.sha256(nonce)
        )
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleSignInClientError.missingIDToken
        }

        return GoogleSignInTokens(
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString,
            nonce: nonce,
            displayName: result.user.profile?.name
        )
        #else
        throw GoogleSignInClientError.missingPresenter
        #endif
    }

    static func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}

private enum GoogleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

private enum GoogleSignInConfig {
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !value.isEmpty else { return nil }
        return value
    }
}

#if canImport(UIKit)
private extension UIApplication {
    var picoTopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .picoTopPresentedViewController
    }
}

private extension UIViewController {
    var picoTopPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.picoTopPresentedViewController
        }

        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.picoTopPresentedViewController
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.picoTopPresentedViewController
        }

        return self
    }
}
#endif
