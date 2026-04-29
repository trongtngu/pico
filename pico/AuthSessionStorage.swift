//
//  AuthSessionStorage.swift
//  pico
//
//  Created by Codex on 29/4/2026.
//

import Foundation
import Security

enum AuthSessionStorageError: LocalizedError {
    case invalidStoredSession
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredSession:
            "The saved login session could not be read."
        case .keychainFailure:
            "The saved login session could not be updated."
        }
    }
}

final class AuthSessionStorage {
    private let service: String
    private let account = "supabase-session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "trongpapaya.pico").auth-session") {
        self.service = service
    }

    func loadSession() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AuthSessionStorageError.keychainFailure(status)
        }

        guard let data = item as? Data else {
            throw AuthSessionStorageError.invalidStoredSession
        }

        do {
            return try decoder.decode(AuthSession.self, from: data)
        } catch {
            throw AuthSessionStorageError.invalidStoredSession
        }
    }

    func saveSession(_ session: AuthSession) throws {
        let data = try encoder.encode(session)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AuthSessionStorageError.keychainFailure(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthSessionStorageError.keychainFailure(addStatus)
        }
    }

    func deleteSession() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
