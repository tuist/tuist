import AppKit
import AuthenticationServices
import SwiftUI
import TuistAuthentication

struct MacLogInView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var errorHandling: ErrorHandling
    @State private var appleSignInDelegate: MacAppleSignInDelegate?
    @State private var isServerSettingsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)

            Image("TuistRoundedIcon")
                .resizable()
                .frame(width: 68, height: 68)
                .padding(.bottom, 24)

            Text("Welcome to Tuist")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            Text("Sign in to access your projects and\ncollaborate with your team")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer(minLength: 52)

            VStack(spacing: 12) {
                serverButton

                MacSocialButton(
                    title: "Sign in with Tuist",
                    style: .primary,
                    icon: "TuistLogo"
                ) {
                    errorHandling.fireAndHandleError {
                        try await authenticationService.signIn()
                    }
                }

                MacSocialButton(
                    title: "Sign in with Apple",
                    style: .secondary,
                    icon: "AppleLogo"
                ) {
                    signInWithApple()
                }

                MacSocialButton(
                    title: "Sign in with Google",
                    style: .secondary,
                    icon: "GoogleLogo"
                ) {
                    errorHandling.fireAndHandleError {
                        try await authenticationService.signInWithGoogle()
                    }
                }

                MacSocialButton(
                    title: "Sign in with GitHub",
                    style: .secondary,
                    icon: "GitHubLogo"
                ) {
                    errorHandling.fireAndHandleError {
                        try await authenticationService.signInWithGitHub()
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 32
                )
                .fill(.ultraThinMaterial)
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 32
                    )
                    .stroke(.white.opacity(0.35), lineWidth: 1)
                }
            )
        }
        .frame(width: 480, height: 680)
        .background {
            Image("LaunchScreenBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isServerSettingsPresented) {
            ServerSettingsView(authenticationService: authenticationService)
        }
    }

    private var serverButton: some View {
        Button {
            isServerSettingsPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Server")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(authenticationService.serverURL.absoluteString)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        appleSignInDelegate = MacAppleSignInDelegate(
            authenticationService: authenticationService,
            errorHandling: errorHandling
        )
        controller.delegate = appleSignInDelegate
        controller.presentationContextProvider = appleSignInDelegate
        controller.performRequests()
    }
}

private struct MacSocialButton: View {
    enum Style {
        case primary
        case secondary
    }

    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let style: Style
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(background)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            ZStack {
                Color(red: 102 / 255, green: 27 / 255, blue: 1)
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .secondary:
            ZStack {
                colorScheme == .dark ? Color(white: 0.12) : .white
                LinearGradient(
                    colors: [.clear, .gray.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .primary
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color(red: 95 / 255, green: 1 / 255, blue: 229 / 255).opacity(0.9)
        case .secondary:
            return .primary.opacity(0.1)
        }
    }
}

@MainActor
private final class MacAppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let authenticationService: AuthenticationService
    private let errorHandling: ErrorHandling

    init(
        authenticationService: AuthenticationService,
        errorHandling: ErrorHandling
    ) {
        self.authenticationService = authenticationService
        self.errorHandling = errorHandling
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        errorHandling.fireAndHandleError {
            try await self.authenticationService.signInWithApple(authorization: authorization)
        }
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        errorHandling.handle(error: error)
    }

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: \.isVisible) ?? NSWindow()
    }
}
