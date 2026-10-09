import AuthenticationServices
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora

public struct LogInView: View {
    @EnvironmentObject var errorHandler: ErrorHandling
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleSignInDelegate: AppleSignInDelegate?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("TuistRoundedIcon")
                .resizable()
                .frame(width: 60, height: 60)
                .padding(.bottom, Noora.Spacing.spacing9)

            Text("Welcome to Tuist")
                .font(.title.weight(.medium))
                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                .padding(.bottom, Noora.Spacing.spacing5)

            signIn
        }
        .disabled(authenticationService.isSigningIn)
        .background(
            Image("LaunchScreenBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var signIn: some View {
        Text("Sign in to access your projects and\ncollaborate with your team")
            .font(.subheadline.weight(.regular))
            .multilineTextAlignment(.center)
            .foregroundColor(Noora.Colors.surfaceLabelPrimary)
            .padding(.bottom, Noora.Spacing.spacing15)

        Spacer()

        if let selfHostedServerURL = authenticationService.selfHostedServerURL {
            Button {
                presentSelfHostedServerAlert()
            } label: {
                HStack(spacing: Noora.Spacing.spacing1) {
                    Image("ServerIcon")
                        .frame(width: 20, height: 20)
                    Text(selfHostedServerURL)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Noora.Spacing.spacing2)
                }
                .foregroundColor(Noora.Colors.buttonSecondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Noora.Spacing.spacing5)
                .padding(.horizontal, Noora.Spacing.spacing4)
                .background(Noora.Colors.surfaceBackgroundPrimary)
                .cornerRadius(Noora.CornerRadius.large)
            }
            .accessibilityHint("Changes the self-hosted server address")
            .padding(.horizontal, Noora.Spacing.spacing9)
            .padding(.bottom, Noora.Spacing.spacing9)
        }

        VStack(spacing: Noora.Spacing.spacing5) {
            SocialButton(
                title: "Sign in with Tuist",
                style: .primary,
                icon: "TuistLogo"
            ) {
                errorHandler.fireAndHandleError { try await authenticationService.signIn() }
            }

            // A self-hosted server's login page lists the providers it has configured, and it can't
            // redeem Apple authorization codes issued for Tuist's bundle ID.
            if authenticationService.selfHostedServerURL == nil {
                SocialButton(
                    title: "Sign in with Apple",
                    style: .secondary,
                    icon: "AppleLogo"
                ) {
                    let request = ASAuthorizationAppleIDProvider().createRequest()
                    request.requestedScopes = [.fullName, .email]

                    let controller = ASAuthorizationController(authorizationRequests: [request])
                    appleSignInDelegate = AppleSignInDelegate(
                        authenticationService: authenticationService,
                        errorHandler: errorHandler
                    )
                    controller.delegate = appleSignInDelegate
                    controller.presentationContextProvider = appleSignInDelegate
                    controller.performRequests()
                }

                SocialButton(
                    title: "Sign in with Google",
                    style: .secondary,
                    icon: "GoogleLogo"
                ) {
                    errorHandler.fireAndHandleError { try await authenticationService.signInWithGoogle() }
                }

                SocialButton(
                    title: "Sign in with GitHub",
                    style: .secondary,
                    icon: "GitHubLogo"
                ) {
                    errorHandler.fireAndHandleError { try await authenticationService.signInWithGitHub() }
                }
            }

            divider

            if authenticationService.selfHostedServerURL == nil {
                SocialButton(
                    title: "Self-hosted server",
                    style: .secondary,
                    icon: "ServerIcon"
                ) {
                    presentSelfHostedServerAlert()
                }
            } else {
                SocialButton(
                    title: "Use Tuist-hosted",
                    style: .secondary
                ) {
                    errorHandler.fireAndHandleError { try await authenticationService.selectServer(nil) }
                }
            }
        }
        .padding(.horizontal, Noora.Spacing.spacing8)
        .padding(.top, Noora.Spacing.spacing9)
        .padding(.bottom, Noora.Spacing.spacing4)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32
            )
            .fill(Color(light: .white.opacity(0.6), dark: Color(hex: 0x0E0E0E, alpha: 0.8)))
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 32
                )
                .stroke(Color(light: Color.white, dark: Color(hex: 0x1F1F1F)), lineWidth: 2)
            )
            .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private var divider: some View {
        HStack(spacing: Noora.Spacing.spacing4) {
            line
            Text("or")
                .font(.footnote)
                .foregroundColor(Noora.Colors.surfaceLabelTertiary)
            line
        }
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(Noora.Colors.surfaceLabelTertiary.opacity(0.3))
            .frame(height: 1)
    }

    private func presentSelfHostedServerAlert() {
        SelfHostedServerAlert.present(serverURL: authenticationService.selfHostedServerURL ?? "") { serverURL in
            errorHandler.fireAndHandleError {
                try await authenticationService.selectServer(serverURL)
                try await authenticationService.signIn()
            }
        }
    }
}

#Preview {
    LogInView()
        .environmentObject(AuthenticationService())
        .withErrorHandling()
}
