//
//  AuthViews.swift
//  pico
//
//  Created by Codex on 25/4/2026.
//

import AuthenticationServices
import CryptoKit
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
    @State private var loginReturnRoute: AuthRoute = .entry
    @State private var signupReturnRoute: AuthRoute = .onboarding
    @State private var signupEntryPoint: AuthRoute = .onboarding

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
                            loginReturnRoute = .entry
                            route = .login
                        }
                    )
                    .navigationBarHidden(true)
                case .onboarding:
                    OnboardingSequenceView(
                        onBackToEntry: {
                            route = .entry
                        },
                        onSignup: {
                            AnalyticsService.track(.signupStarted(method: "email", entryPoint: "onboarding"))
                            signupEntryPoint = .onboarding
                            signupReturnRoute = .onboarding
                            route = .signup
                        },
                        onLogin: {
                            loginReturnRoute = .onboarding
                            route = .login
                        }
                    )
                    .navigationBarHidden(true)
                case .login:
                    LoginView {
                        signupEntryPoint = .login
                        signupReturnRoute = .login
                        route = .signupOptions
                    }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                route = loginReturnRoute
                            } label: {
                                PicoIcon(.chevronLeftRegular, size: 22)
                                    .foregroundStyle(PicoColors.textPrimary)
                            }
                            .accessibilityLabel(Text("Back"))
                        }
                    }
                    .toolbarBackground(PicoColors.appBackground, for: .navigationBar)
                case .signupOptions:
                    SignupOptionsView(
                        entryPoint: signupEntryPoint.analyticsEntryPoint,
                        onBack: {
                            route = signupReturnRoute
                        },
                        onEmailSignup: {
                            AnalyticsService.track(.signupStarted(
                                method: "email",
                                entryPoint: signupEntryPoint.analyticsEntryPoint
                            ))
                            signupReturnRoute = .signupOptions
                            route = .signup
                        },
                        onLogin: {
                            loginReturnRoute = .signupOptions
                            route = .login
                        }
                    )
                    .navigationBarHidden(true)
                case .signup:
                    SignupFlowView(
                        onBackToStart: {
                            route = signupReturnRoute
                        },
                        onLogin: {
                            loginReturnRoute = .signup
                            route = .login
                        },
                        entryPoint: signupEntryPoint.analyticsEntryPoint,
                        completesOnboarding: signupReturnRoute == .onboarding
                    )
                    .navigationBarHidden(true)
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
    case login
    case signupOptions
    case signup

    var analyticsEntryPoint: String {
        switch self {
        case .onboarding:
            "onboarding"
        case .login:
            "login"
        case .entry:
            "entry"
        case .signupOptions:
            "signup"
        case .signup:
            "signup"
        }
    }
}

struct SignupOptionsView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore

    let entryPoint: String
    let onBack: () -> Void
    let onEmailSignup: () -> Void
    let onLogin: () -> Void

    @State private var appleSignInNonce: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        PicoIcon(.chevronLeftRegular, size: 22)
                            .foregroundStyle(PicoColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Back"))

                    Spacer()
                }
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.top, max(0, proxy.safeAreaInsets.top))
                .frame(height: proxy.safeAreaInsets.top + 56, alignment: .top)
                .background(PicoColors.appBackground)

                Spacer(minLength: PicoSpacing.compact)

                VStack(spacing: PicoSpacing.largeSection) {
                    Text("Create an account")
                        .font(PicoTypography.sectionTitle)
                        .foregroundStyle(PicoColors.textPrimary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: PicoSpacing.iconTextGap) {
                        Button("Continue with email", action: onEmailSignup)
                            .buttonStyle(PicoPrimaryButtonStyle())

                        PicoAuthDivider()
                            .padding(.top, PicoSpacing.compact)

                        PicoGoogleSignInButton(
                            title: "Google",
                            isLoading: sessionStore.isLoading
                        ) {
                            AnalyticsService.track(.signupStarted(method: "google", entryPoint: entryPoint))
                            Task {
                                await sessionStore.signInWithGoogle()
                            }
                        }

                        PicoAppleSignInButton(
                            isLoading: sessionStore.isLoading,
                            onRequest: handleAppleSignInRequest,
                            onCompletion: handleAppleSignInCompletion
                        )

                        HStack(spacing: PicoSpacing.tiny) {
                            Text("Already have an account?")
                                .font(PicoTypography.caption)
                                .foregroundStyle(PicoColors.textSecondary)

                            Button("Log in", action: onLogin)
                                .font(PicoTypography.captionSemibold)
                                .foregroundStyle(PicoColors.primary)
                                .buttonStyle(.plain)
                        }

                        if let notice = sessionStore.notice {
                            Text(notice)
                                .font(PicoTypography.caption)
                                .foregroundStyle(PicoColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(PicoSpacing.standard)
                                .background(
                                    RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                                        .fill(PicoColors.softSurface)
                                )
                        }
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .frame(maxWidth: .infinity)

                Spacer(minLength: PicoSpacing.compact)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            sessionStore.notice = nil
        }
        .onDisappear {
            sessionStore.notice = nil
        }
    }

    private func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        AnalyticsService.track(.signupStarted(method: "apple", entryPoint: entryPoint))

        let nonce = LoginAppleSignInNonce.random()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = LoginAppleSignInNonce.sha256(nonce)
        sessionStore.notice = nil
    }

    private func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                sessionStore.notice = "Sign in with Apple did not return a valid identity token."
                return
            }

            let nonce = appleSignInNonce
            let fullName = credential.fullName
            Task {
                await sessionStore.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            }
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            sessionStore.notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore

    let onSignup: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var appleSignInNonce: String?

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        normalizedEmail.contains("@")
            && password.count >= 6
            && !sessionStore.isLoading
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: PicoSpacing.section) {
                    Text("Welcome back")
                    .font(PicoTypography.sectionTitle)
                    .foregroundStyle(PicoColors.textPrimary)
                    .multilineTextAlignment(.center)

                    VStack(spacing: PicoSpacing.iconTextGap) {
                        TextField(
                            "",
                            text: $email,
                            prompt: Text("Email").foregroundStyle(PicoColors.textMuted)
                        )
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .foregroundStyle(PicoColors.textPrimary)
                        .authFieldStyle()
                        .onChange(of: email) {
                            sessionStore.notice = nil
                        }

                        SecureField(
                            "",
                            text: $password,
                            prompt: Text("Password").foregroundStyle(PicoColors.textMuted)
                        )
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            guard canSubmit else { return }

                            Task {
                                await submit()
                            }
                        }
                        .foregroundStyle(PicoColors.textPrimary)
                        .authFieldStyle()
                        .onChange(of: password) {
                            sessionStore.notice = nil
                        }

                        if let notice = sessionStore.notice {
                            Text(notice)
                                .font(PicoTypography.caption)
                                .foregroundStyle(PicoColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(PicoSpacing.standard)
                                .background(
                                    RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                                        .fill(PicoColors.softSurface)
                                )
                        }

                        Button {
                            Task {
                                await submit()
                            }
                        } label: {
                            ZStack {
                                Text("Log in")
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)

                                if sessionStore.isLoading {
                                    HStack {
                                        Spacer()

                                        ProgressView()
                                            .tint(PicoColors.textOnPrimary)
                                    }
                                }
                            }
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.62)
                        .buttonStyle(PicoPrimaryButtonStyle())

                        PicoAuthDivider()
                            .padding(.top, PicoSpacing.compact)

                        PicoGoogleSignInButton(
                            title: "Google",
                            isLoading: sessionStore.isLoading
                        ) {
                            Task {
                                await sessionStore.signInWithGoogle()
                            }
                        }

                        PicoAppleSignInButton(
                            isLoading: sessionStore.isLoading,
                            onRequest: handleAppleSignInRequest,
                            onCompletion: handleAppleSignInCompletion
                        )
                    }

                    HStack(spacing: PicoSpacing.tiny) {
                        Text("Don't have an account?")
                            .font(PicoTypography.caption)
                            .foregroundStyle(PicoColors.textSecondary)

                        Button("Sign up", action: onSignup)
                            .font(PicoTypography.captionSemibold)
                            .foregroundStyle(PicoColors.primary)
                            .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.vertical, PicoSpacing.largeSection)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .toolbarColorScheme(.light, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear {
            sessionStore.notice = nil
        }
        .onDisappear {
            sessionStore.notice = nil
        }
    }

    private func submit() async {
        guard canSubmit else { return }

        await sessionStore.signIn(email: normalizedEmail, password: password)
    }

    private func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = LoginAppleSignInNonce.random()
        appleSignInNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = LoginAppleSignInNonce.sha256(nonce)
        sessionStore.notice = nil
    }

    private func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                sessionStore.notice = "Sign in with Apple did not return a valid identity token."
                return
            }

            let nonce = appleSignInNonce
            let fullName = credential.fullName
            Task {
                await sessionStore.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
            }
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            sessionStore.notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SignupFlowView: View {
    @EnvironmentObject private var sessionStore: AuthSessionStore

    let onBackToStart: () -> Void
    let onLogin: () -> Void
    let entryPoint: String
    let completesOnboarding: Bool

    @State private var currentStep: SignupStep = .email
    @State private var draft = SignupDraft()
    @State private var showsDuplicateEmailLoginPrompt = false
    @State private var hasTrackedSignupCompletion = false
    @State private var hasTrackedOnboardingCompletion = false

    private var currentIndex: Int {
        SignupStep.ordered.firstIndex(of: currentStep) ?? 0
    }

    private var normalizedEmail: String {
        draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedUsername: String {
        draft.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedFirstName: String {
        draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsernameValid: Bool {
        normalizedUsername.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil
    }

    private var isFirstNameValid: Bool {
        (1...40).contains(normalizedFirstName.count)
    }

    private var isPasswordValid: Bool {
        draft.password.count >= 6
            && draft.password.range(of: "[^A-Za-z0-9\\s]", options: .regularExpression) != nil
    }

    private var canContinue: Bool {
        guard !sessionStore.isLoading else { return false }

        switch currentStep {
        case .email:
            return normalizedEmail.contains("@")
        case .firstName:
            return isFirstNameValid
        case .username:
            return isUsernameValid
        case .password:
            return isPasswordValid
        }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                SignupProgressHeader(
                    currentIndex: currentIndex,
                    totalCount: SignupStep.ordered.count,
                    onBack: goBack,
                    topInset: proxy.safeAreaInsets.top
                )

                VStack(spacing: PicoSpacing.section) {
                    VStack(spacing: PicoSpacing.compact) {
                        Text(currentStep.title)
                            .font(PicoTypography.sectionTitle)
                            .foregroundStyle(PicoColors.textPrimary)
                            .multilineTextAlignment(.center)

                        if let subtitle = currentStep.subtitle {
                            Text(subtitle)
                                .font(PicoTypography.body)
                                .foregroundStyle(PicoColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    signupField

                    if sessionStore.notice != nil {
                        signupNotice
                    }

                    Button {
                        Task {
                            await handlePrimaryAction()
                        }
                    } label: {
                        ZStack {
                            Text(currentStep == SignupStep.ordered.last ? "Create account" : "Continue")
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)

                            if sessionStore.isLoading {
                                HStack {
                                    Spacer()

                                    ProgressView()
                                        .tint(PicoColors.textOnPrimary)
                                }
                            }
                        }
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.62)
                    .buttonStyle(PicoPrimaryButtonStyle())

                    Spacer(minLength: PicoSpacing.largeSection)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, PicoSpacing.standard)
                .padding(.top, PicoSpacing.section)
                .padding(.bottom, max(PicoSpacing.section, proxy.safeAreaInsets.bottom + PicoSpacing.standard))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(PicoColors.appBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            sessionStore.notice = nil
        }
        .onDisappear {
            sessionStore.notice = nil
        }
    }

    @ViewBuilder
    private var signupField: some View {
        switch currentStep {
        case .email:
            TextField(
                "",
                text: $draft.email,
                prompt: Text("Email").foregroundStyle(PicoColors.textMuted)
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocorrectionDisabled()
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onChange(of: draft.email) {
                showsDuplicateEmailLoginPrompt = false
                sessionStore.notice = nil
            }
        case .firstName:
            TextField(
                "",
                text: $draft.firstName,
                prompt: Text("First name").foregroundStyle(PicoColors.textMuted)
            )
            .textContentType(.givenName)
            .autocorrectionDisabled()
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onChange(of: draft.firstName) {
                sessionStore.notice = nil
            }
        case .username:
            TextField(
                "",
                text: $draft.username,
                prompt: Text("Username").foregroundStyle(PicoColors.textMuted)
            )
            .textInputAutocapitalization(.never)
            .textContentType(.username)
            .autocorrectionDisabled()
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onChange(of: draft.username) {
                draft.username = normalizedUsername
                sessionStore.notice = nil
            }
        case .password:
            SecureField(
                "",
                text: $draft.password,
                prompt: Text("Password").foregroundStyle(PicoColors.textMuted)
            )
            .textContentType(.newPassword)
            .foregroundStyle(PicoColors.textPrimary)
            .authFieldStyle()
            .onChange(of: draft.password) {
                sessionStore.notice = nil
            }
        }
    }

    private func goBack() {
        guard currentIndex > 0 else {
            onBackToStart()
            return
        }

        currentStep = SignupStep.ordered[currentIndex - 1]
    }

    private func handlePrimaryAction() async {
        guard canContinue else { return }

        if currentStep == .email {
            let email = normalizedEmail
            let isEmailAvailable = await sessionStore.validateEmailAvailability(email)
            guard email == normalizedEmail else {
                return
            }

            guard isEmailAvailable else {
                showsDuplicateEmailLoginPrompt = sessionStore.notice == AuthServiceError.emailUnavailable.errorDescription
                return
            }

            showsDuplicateEmailLoginPrompt = false
        }

        if currentStep == .username {
            let username = normalizedUsername
            guard await sessionStore.validateUsernameAvailability(username),
                  username == normalizedUsername
            else {
                return
            }
        }

        guard currentIndex < SignupStep.ordered.index(before: SignupStep.ordered.endIndex) else {
            await submit()
            return
        }

        currentStep = SignupStep.ordered[currentIndex + 1]
    }

    @ViewBuilder
    private var signupNotice: some View {
        if showsDuplicateEmailLoginPrompt, currentStep == .email {
            VStack(alignment: .leading, spacing: PicoSpacing.tiny) {
                Text("Looks like you already have an account.")
                    .foregroundStyle(PicoColors.textSecondary)

                Button("Log in instead.") {
                    sessionStore.notice = nil
                    onLogin()
                }
                .font(PicoTypography.caption.weight(.semibold))
                .foregroundStyle(PicoColors.primary)
                .buttonStyle(.plain)
            }
            .font(PicoTypography.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(PicoColors.softSurface)
            )
        } else if let notice = sessionStore.notice {
            Text(notice)
                .font(PicoTypography.caption)
                .foregroundStyle(PicoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PicoSpacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                        .fill(PicoColors.softSurface)
                )
        }
    }

    private func submit() async {
        guard normalizedEmail.contains("@"),
              isFirstNameValid,
              isUsernameValid,
              isPasswordValid
        else {
            return
        }

        await sessionStore.signUp(
            email: normalizedEmail,
            password: draft.password,
            username: normalizedUsername,
            displayName: normalizedFirstName,
            avatarConfig: AvatarCatalog.defaultConfig
        )

        let didCreateAccount = sessionStore.session != nil
            || sessionStore.notice?.hasPrefix("Account created.") == true
        if didCreateAccount {
            trackSignupCompletionIfNeeded()
            trackOnboardingCompletionIfNeeded()
        }

        if sessionStore.session == nil,
           sessionStore.notice?.hasPrefix("Account created.") == true {
            await sessionStore.signIn(email: normalizedEmail, password: draft.password)
        }
    }

    private func trackSignupCompletionIfNeeded() {
        guard !hasTrackedSignupCompletion else { return }
        hasTrackedSignupCompletion = true
        AnalyticsService.track(.signupCompleted(method: "email", entryPoint: entryPoint))
    }

    private func trackOnboardingCompletionIfNeeded() {
        guard completesOnboarding, !hasTrackedOnboardingCompletion else { return }
        hasTrackedOnboardingCompletion = true
        AnalyticsService.track(.onboardingCompleted())
    }
}

enum SignupStep: String, CaseIterable, Identifiable {
    case email
    case firstName
    case username
    case password

    static let ordered: [SignupStep] = [
        .email,
        .firstName,
        .username,
        .password
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .email:
            "What's your email?"
        case .firstName:
            "What's your first name?"
        case .username:
            "Choose a username"
        case .password:
            "Create a password"
        }
    }

    var subtitle: String? {
        switch self {
        case .email:
            nil
        case .firstName:
            nil
        case .username:
            "This is how friends will find you"
        case .password:
            "At least 6 characters\nOne or more special characters"
        }
    }
}

struct SignupDraft {
    var email = ""
    var username = ""
    var firstName = ""
    var password = ""
}

private struct SignupProgressHeader: View {
    let currentIndex: Int
    let totalCount: Int
    let onBack: () -> Void
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: PicoSpacing.compact) {
            Button(action: onBack) {
                PicoIcon(.chevronLeftRegular, size: 22)
                    .foregroundStyle(PicoColors.textPrimary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            SignupPageIndicator(
                currentIndex: currentIndex,
                totalCount: totalCount
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PicoSpacing.standard)
        .padding(.top, max(0, topInset))
        .frame(height: topInset + 56, alignment: .top)
        .background(PicoColors.appBackground)
    }
}

private struct SignupPageIndicator: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? PicoColors.primary : PicoColors.border)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Signup step \(currentIndex + 1) of \(totalCount)"))
    }
}

private struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PicoTypography.body)
            .padding(.horizontal, PicoSpacing.standard)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(PicoColors.softSurface)
            )
    }
}

private enum LoginAppleSignInNonce {
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

private extension View {
    func authFieldStyle() -> some View {
        modifier(AuthFieldStyle())
    }
}
