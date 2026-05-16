//
//  BotChallengeView.swift
//  pico
//
//  Created by Codex on 16/5/2026.
//

import Foundation
import SwiftUI
import WebKit

enum BotChallengeConfiguration {
    static var isSignupChallengeEnabled: Bool {
        turnstileSiteKey != nil && turnstileBaseURL != nil
    }

    static var turnstileSiteKey: String? {
        sanitizedInfoPlistValue(forKey: "PICO_TURNSTILE_SITE_KEY")
    }

    static var turnstileBaseURL: URL? {
        if let urlString = sanitizedInfoPlistValue(forKey: "PICO_TURNSTILE_CHALLENGE_URL"),
           let url = URL(string: urlString) {
            return url
        }

        return nil
    }

    private static func sanitizedInfoPlistValue(forKey key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else {
            return nil
        }

        return value
    }
}

struct TurnstileChallengeView: UIViewRepresentable {
    let challengeID: UUID
    let siteKey: String
    let baseURL: URL
    let action: String
    let onToken: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(challengeID: challengeID, onToken: onToken, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        context.coordinator.loadChallenge(in: webView, siteKey: siteKey, baseURL: baseURL, action: action)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.challengeID != challengeID else { return }

        context.coordinator.challengeID = challengeID
        context.coordinator.loadChallenge(in: webView, siteKey: siteKey, baseURL: baseURL, action: action)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageHandlerName = "picoTurnstile"

        var challengeID: UUID
        private let onToken: (String) -> Void
        private let onFailure: () -> Void
        private var hasCompleted = false

        init(challengeID: UUID, onToken: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
            self.challengeID = challengeID
            self.onToken = onToken
            self.onFailure = onFailure
        }

        func loadChallenge(in webView: WKWebView, siteKey: String, baseURL: URL, action: String) {
            hasCompleted = false
            webView.loadHTMLString(
                Self.html(siteKey: siteKey, action: action),
                baseURL: baseURL
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard !hasCompleted,
                  let body = message.body as? [String: Any],
                  let status = body["status"] as? String
            else {
                return
            }

            switch status {
            case "token":
                guard let token = body["token"] as? String, !token.isEmpty else {
                    fail()
                    return
                }

                hasCompleted = true
                onToken(token)
            case "error", "expired", "timeout":
                fail()
            default:
                break
            }
        }

        private func fail() {
            guard !hasCompleted else { return }

            hasCompleted = true
            onFailure()
        }

        private static func html(siteKey: String, action: String) -> String {
            let siteKeyLiteral = javaScriptStringLiteral(siteKey)
            let actionLiteral = javaScriptStringLiteral(action)

            return """
            <!doctype html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
              <style>
                html, body, #turnstile {
                  width: 1px;
                  height: 1px;
                  margin: 0;
                  overflow: hidden;
                  background: transparent;
                }
              </style>
            </head>
            <body>
              <div id="turnstile"></div>
              <script>
                const siteKey = \(siteKeyLiteral);
                const action = \(actionLiteral);
                let didComplete = false;

                function post(message) {
                  if (didComplete) { return; }
                  if (message.status !== "token") { didComplete = true; }
                  window.webkit.messageHandlers.\(messageHandlerName).postMessage(message);
                }

                function renderChallenge() {
                  if (!window.turnstile) {
                    window.setTimeout(renderChallenge, 50);
                    return;
                  }

                  const widgetID = window.turnstile.render("#turnstile", {
                    sitekey: siteKey,
                    action: action,
                    size: "invisible",
                    callback: function(token) {
                      didComplete = true;
                      window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                        status: "token",
                        token: token
                      });
                    },
                    "error-callback": function(code) {
                      post({ status: "error", code: String(code) });
                    },
                    "expired-callback": function() {
                      post({ status: "expired" });
                    }
                  });

                  window.turnstile.execute(widgetID);
                }

                window.addEventListener("load", renderChallenge);
                window.setTimeout(function() {
                  post({ status: "timeout" });
                }, 20000);
              </script>
            </body>
            </html>
            """
        }

        private static func javaScriptStringLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8) else {
                return "\"\""
            }

            return string
        }
    }
}
