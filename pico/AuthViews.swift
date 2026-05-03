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
            if sessionStore.isRestoringSession {
                ProgressView()
                    .tint(PicoColors.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PicoColors.appBackground.ignoresSafeArea())
            } else if sessionStore.session == nil {
                AuthRootView()
                    .environmentObject(sessionStore)
            } else {
                AppShellView()
                    .environmentObject(sessionStore)
            }
        }
        .task {
            await sessionStore.restoreSessionIfNeeded()
        }
    }
}

private struct AuthRootView: View {
    @State private var route: AuthRoute = .entry
    @State private var mode: AuthMode = .login

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .entry:
                    AuthEntryView(
                        onGetStarted: {
                            route = .onboarding
                        },
                        onLogin: {
                            mode = .login
                            route = .auth
                        }
                    )
                    .navigationBarHidden(true)
                case .onboarding:
                    OnboardingSequenceView(
                        onBackToEntry: {
                            route = .entry
                        },
                        onSignup: {
                            mode = .signup
                            route = .auth
                        },
                        onLogin: {
                            mode = .login
                            route = .auth
                        }
                    )
                    .navigationBarHidden(true)
                case .auth:
                    AuthFormView(mode: $mode)
                        .navigationTitle(mode.title)
                        .toolbarTitleDisplayMode(.large)
                        .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
                }
            }
            .background(PicoColors.appBackground.ignoresSafeArea())
            .tint(PicoColors.primary)
        }
    }
}

private enum AuthRoute {
    case entry
    case onboarding
    case auth
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
                TextField(
                    "",
                    text: $email,
                    prompt: Text("Email").foregroundStyle(PicoColors.textMuted)
                )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .foregroundStyle(PicoColors.textPrimary)

                SecureField(
                    "",
                    text: $password,
                    prompt: Text("Password").foregroundStyle(PicoColors.textMuted)
                )
                    .textContentType(mode == .login ? .password : .newPassword)
                    .foregroundStyle(PicoColors.textPrimary)

                if mode == .signup {
                    SecureField(
                        "",
                        text: $confirmPassword,
                        prompt: Text("Confirm password").foregroundStyle(PicoColors.textMuted)
                    )
                        .textContentType(.newPassword)
                        .foregroundStyle(PicoColors.textPrimary)
                }
            }
            .listRowBackground(PicoColors.softSurface)

            if mode == .signup {
                Section {
                    TextField(
                        "",
                        text: $username,
                        prompt: Text("Username").foregroundStyle(PicoColors.textMuted)
                    )
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .onChange(of: username) {
                            username = normalizedUsername
                        }
                        .foregroundStyle(PicoColors.textPrimary)

                    TextField(
                        "",
                        text: $displayName,
                        prompt: Text("Display name").foregroundStyle(PicoColors.textMuted)
                    )
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .foregroundStyle(PicoColors.textPrimary)
                } header: {
                    Text("Profile")
                        .foregroundStyle(PicoColors.textSecondary)
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
        .toolbarColorScheme(.light, for: .navigationBar)
        .preferredColorScheme(.light)
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

enum AuthMode: String, CaseIterable, Identifiable {
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
