//
//  AuthViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import SwiftUI

struct AuthGateView: View {
    @StateObject private var sessionStore = AuthSessionStore()

    var body: some View {
        Group {
            if sessionStore.session == nil {
                AuthRootView()
                    .environmentObject(sessionStore)
            } else {
                AppShellView()
                    .environmentObject(sessionStore)
            }
        }
    }
}

private struct AuthRootView: View {
    @State private var mode: AuthMode = .login

    var body: some View {
        NavigationStack {
            AuthFormView(mode: $mode)
                .navigationTitle(mode.title)
                .toolbarTitleDisplayMode(.large)
                .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
                .background(PicoColors.appBackground.ignoresSafeArea())
                .tint(PicoColors.primary)
        }
    }
}

private struct AuthFormView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore
    @Binding var mode: AuthMode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var displayName = ""

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsernameValid: Bool {
        normalizedUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil
    }

    private var isDisplayNameValid: Bool {
        (1...40).contains(normalizedDisplayName.count)
    }

    private var canSubmit: Bool {
        let hasCredentials = email.contains("@") && password.count >= 6
        guard mode == .signup else { return hasCredentials }
        return hasCredentials
            && password == confirmPassword
            && isUsernameValid
            && isDisplayNameValid
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(PicoColors.softSurface)

            Section {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(mode == .login ? .password : .newPassword)

                if mode == .signup {
                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
            }
            .listRowBackground(PicoColors.softSurface)

            if mode == .signup {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .onChange(of: username) {
                            username = normalizedUsername
                        }

                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Username can use lowercase letters, numbers, and underscores.")
                        .foregroundStyle(PicoColors.textSecondary)
                }
                .listRowBackground(PicoColors.softSurface)

            }

            if let notice = sessionStore.notice {
                Section {
                    Text(notice)
                        .foregroundStyle(PicoColors.textSecondary)
                }
                .listRowBackground(PicoColors.softSurface)
            }

            Section {
                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    HStack {
                        Text(mode.actionTitle)
                        Spacer()
                        if sessionStore.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSubmit || sessionStore.isLoading)
                .foregroundStyle(PicoColors.primary)
            }
            .listRowBackground(PicoColors.softSurface)
        }
        .scrollContentBackground(.hidden)
        .background(PicoColors.appBackground.ignoresSafeArea())
        .tint(PicoColors.primary)
        .onChange(of: mode) {
            sessionStore.notice = nil
            confirmPassword = ""
        }
    }

    private func submit() async {
        switch mode {
        case .login:
            await sessionStore.signIn(email: email, password: password)
        case .signup:
            await sessionStore.signUp(
                email: email,
                password: password,
                username: normalizedUsername,
                displayName: normalizedDisplayName,
                avatarConfig: AvatarCatalog.defaultConfig
            )
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case signup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            "Login"
        case .signup:
            "Sign Up"
        }
    }

    var actionTitle: String {
        switch self {
        case .login:
            "Log In"
        case .signup:
            "Create Account"
        }
    }
}
