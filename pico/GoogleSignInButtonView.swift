//
//  GoogleSignInButtonView.swift
//  pico
//
//  Created by Codex on 13/5/2026.
//

import AuthenticationServices
import GoogleSignIn
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PicoAuthDivider: View {
    var body: some View {
        HStack(spacing: PicoSpacing.iconTextGap) {
            Rectangle()
                .fill(PicoColors.border)
                .frame(height: 1)

            Text("or sign in with")
                .font(PicoTypography.captionSemibold)
                .foregroundStyle(PicoColors.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(PicoColors.border)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PicoGoogleSignInButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PicoSpacing.compact) {
                GoogleSignInSDKLogo()
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(PicoTypography.button)
                    .foregroundStyle(PicoColors.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(PicoColors.textPrimary)
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.trailing, PicoSpacing.standard)
            }
            .frame(height: 52)
            .padding(.horizontal, PicoSpacing.standard)
            .background(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous)
                    .stroke(PicoColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.62 : 1)
    }
}

private struct GoogleSignInSDKLogo: View {
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                EmptyView()
            }
            #else
            EmptyView()
            #endif
        }
        .accessibilityHidden(true)
    }

    #if canImport(UIKit)
    private static var image: UIImage? {
        guard let url = Bundle.googleSignInResourceURL(name: "google", withExtension: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
    #endif
}

private extension Bundle {
    static func googleSignInResourceURL(name: String, withExtension ext: String) -> URL? {
        googleSignInBundle()?.url(forResource: name, withExtension: ext)
    }

    static func googleSignInBundle() -> Bundle? {
        let bundleName = "GoogleSignIn_GoogleSignIn"

        if let mainPath = Bundle.main.path(forResource: bundleName, ofType: "bundle") {
            return Bundle(path: mainPath)
        }

        let classBundle = Bundle(for: GIDSignIn.self)
        if let classPath = classBundle.path(forResource: bundleName, ofType: "bundle") {
            return Bundle(path: classPath)
        }

        return nil
    }
}

struct PicoAppleSignInButton: View {
    let isLoading: Bool
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: onRequest,
            onCompletion: onCompletion
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
        .overlay {
            HStack(spacing: PicoSpacing.compact) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 24, height: 24)

                Text("Apple")
                    .font(PicoTypography.button)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.white)
            .padding(.horizontal, PicoSpacing.standard)
            .frame(height: 52)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: PicoRadius.medium, style: .continuous))
            .allowsHitTesting(false)
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.62 : 1)
        .accessibilityLabel(Text("Apple"))
    }
}
