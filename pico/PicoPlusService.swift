//
//  PicoPlusService.swift
//  pico
//
//  Created by Codex on 15/5/2026.
//

import Foundation
#if canImport(SuperwallKit)
import SuperwallKit
#endif

enum PicoPlusServiceError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case paywallNotConfigured
    case paywallSkipped(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Add your Supabase project URL and anon key in SupabaseConfig.swift."
        case .invalidResponse:
            "Supabase returned a response the app could not read."
        case .paywallNotConfigured:
            "Pico Plus is not ready yet."
        case .paywallSkipped(let reason):
            reason
        case .requestFailed(let message):
            message
        }
    }
}

enum PicoPlusPaywallOutcome: Equatable {
    case purchased
    case restored
    case declined
    case skipped(String)
}

final class PicoPlusService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    static func configurePaywallProvider() {
        guard let apiKey = configuredSuperwallAPIKey else { return }

        #if canImport(SuperwallKit)
        Superwall.configure(apiKey: apiKey)
        #endif
    }

    @MainActor
    func identifyUser(session: AuthSession?, profile: UserProfile?) {
        #if canImport(SuperwallKit)
        guard Self.configuredSuperwallAPIKey != nil else { return }

        guard let user = session?.user else {
            Superwall.shared.reset()
            return
        }

        let userID = user.id.uuidString
        Superwall.shared.identify(userId: userID)
        Superwall.shared.setUserAttributes([
            "user_id": userID,
            "email": user.email,
            "username": profile?.username,
            "display_name": profile?.displayName
        ])
        #endif
    }

    @MainActor
    func presentPaywall(placement: PicoPlusPlacement) async throws -> PicoPlusPaywallOutcome {
        #if canImport(SuperwallKit)
        guard Self.configuredSuperwallAPIKey != nil else {
            throw PicoPlusServiceError.paywallNotConfigured
        }

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            func resume(_ result: Result<PicoPlusPaywallOutcome, Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let handler = PaywallPresentationHandler()
            handler.onDismiss { _, result in
                switch result {
                case .purchased:
                    resume(.success(.purchased))
                case .restored:
                    resume(.success(.restored))
                case .declined:
                    resume(.success(.declined))
                }
            }
            handler.onSkip { reason in
                resume(.failure(PicoPlusServiceError.paywallSkipped(reason.description)))
            }
            handler.onError { error in
                resume(.failure(error))
            }

            Superwall.shared.register(
                placement: placement.rawValue,
                handler: handler
            )
        }
        #else
        throw PicoPlusServiceError.paywallNotConfigured
        #endif
    }

    func fetchEntitlement(for authSession: AuthSession) async throws -> PicoPlusEntitlement {
        let response: [PicoPlusEntitlementResponse] = try await send(
            path: "/rest/v1/rpc/fetch_pico_plus_entitlement",
            method: "POST",
            body: EmptyPicoPlusRequest(),
            accessToken: authSession.accessToken
        )

        return response.first?.picoPlusEntitlement ?? .free
    }

    private static var configuredSuperwallAPIKey: String? {
        let candidates = [
            Bundle.main.object(forInfoDictionaryKey: "SUPERWALL_API_KEY") as? String,
            ProcessInfo.processInfo.environment["SUPERWALL_API_KEY"]
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        accessToken: String
    ) async throws -> ResponseBody {
        guard SupabaseConfig.isConfigured, let baseURL = SupabaseConfig.projectURL else {
            throw PicoPlusServiceError.missingConfiguration
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw PicoPlusServiceError.missingConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PicoPlusServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(PicoPlusSupabaseErrorResponse.self, from: data)
            let responseBody = String(data: data, encoding: .utf8)
            throw PicoPlusServiceError.requestFailed(
                errorResponse?.displayMessage
                    ?? responseBody
                    ?? "Supabase request failed with status \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw PicoPlusServiceError.invalidResponse
        }
    }
}

private struct EmptyPicoPlusRequest: Encodable {}

private struct PicoPlusEntitlementResponse: Decodable {
    let isActive: Bool
    let status: String?
    let provider: String?
    let currentPeriodEnd: String?

    var picoPlusEntitlement: PicoPlusEntitlement {
        PicoPlusEntitlement(
            isActive: isActive,
            status: status,
            provider: provider,
            currentPeriodEnd: currentPeriodEnd.flatMap(FocusDateFormatter.date(from:))
        )
    }
}

private struct PicoPlusSupabaseErrorResponse: Decodable {
    let message: String?
    let details: String?
    let hint: String?

    var displayMessage: String? {
        message ?? details ?? hint
    }
}
