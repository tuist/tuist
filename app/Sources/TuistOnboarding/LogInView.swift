import AuthenticationServices
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora

public struct LogInView: View {
    @EnvironmentObject var errorHandler: ErrorHandling
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var appleSignInDelegate: AppleSignInDelegate?

    public init() {}

    public var body: some View {
        content
            .disabled(authenticationService.isSigningIn)
            .background(
                Image("LaunchScreenBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 27.1, *), horizontalSizeClass == .regular {
                ArrangementView {
                    signInContent(includesWelcome: false)
                } secondary: {
                    ScrollView {
                        welcome
                            .padding(Noora.Spacing.spacing8)
                    }
                    .defaultScrollAnchor(.center)
                }
                .arrangementViewStyle(.split)
            } else {
                signInContent(includesWelcome: true)
            }
        #else
            signInContent(includesWelcome: true)
        #endif
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Noora.Spacing.spacing6) {
            Image("TuistRoundedIcon")
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
                Text("Welcome to Tuist")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Sign in to browse your projects and app previews.")
                    .font(.body)
                    .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signInContent(includesWelcome: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Noora.Spacing.spacing9) {
                    if includesWelcome {
                        welcome
                    }
                    signIn
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, Noora.Spacing.spacing8)
                .padding(.vertical, Noora.Spacing.spacing8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    private var signIn: some View {
        VStack(spacing: Noora.Spacing.spacing5) {
            SocialButton(
                title: "Sign in with Tuist",
                style: .primary,
                icon: "TuistLogo"
            ) {
                signInToTuistHosted { try await authenticationService.signIn() }
            }

            divider
                .padding(.vertical, Noora.Spacing.spacing4)

            SocialButton(
                title: "Sign in with Apple",
                style: .secondary,
                icon: "AppleLogo"
            ) {
                signInToTuistHosted {
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
            }

            SocialButton(
                title: "Sign in with Google",
                style: .secondary,
                icon: "GoogleLogo"
            ) {
                signInToTuistHosted { try await authenticationService.signInWithGoogle() }
            }

            SocialButton(
                title: "Sign in with GitHub",
                style: .secondary,
                icon: "GitHubLogo"
            ) {
                signInToTuistHosted { try await authenticationService.signInWithGitHub() }
            }

            Button {
                presentSelfHostedServerAlert()
            } label: {
                Label("Self-hosted server", systemImage: "server.rack")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Noora.Colors.buttonEnabledLabel)
            .padding(.top, Noora.Spacing.spacing4)
        }
        .frame(maxWidth: .infinity)
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

    /// The saved self-hosted server only prefills the prompt, so the other buttons always sign in to Tuist-hosted.
    private func signInToTuistHosted(_ signIn: @escaping () async throws -> Void) {
        errorHandler.fireAndHandleError {
            try await authenticationService.selectServer(nil)
            try await signIn()
        }
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
