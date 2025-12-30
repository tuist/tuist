import AuthenticationServices
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora

public struct LogInView: View {
    @EnvironmentObject var errorHandler: ErrorHandling
    @StateObject private var authenticationService = AuthenticationService()
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

            Text("Sign in to access your projects and\ncollaborate with your team")
                .font(.subheadline.weight(.regular))
                .multilineTextAlignment(.center)
                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                .padding(.bottom, 80)

            Spacer()

            VStack(spacing: Noora.Spacing.spacing5) {
                SocialButton(
                    title: "Sign in with Tuist",
                    style: .primary,
                    icon: "TuistLogo"
                ) {
                    errorHandler.fireAndHandleError { try await authenticationService.signIn() }
                }

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
        .background(
            Image("LaunchScreenBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    LogInView()
}
