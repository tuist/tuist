import AuthenticationServices
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora

public struct LogInView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @StateObject private var authenticationService = AuthenticationService()
    @Environment(\.colorScheme) private var colorScheme

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
                    errorHandling.fireAndHandleError { try await authenticationService.signIn() }
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        errorHandling.fireAndHandleError {
                            try await authenticationService.signInWithApple(authorization: authorization)
                        }
                    case let .failure(error):
                        errorHandling.handle(error: error)
                    }
                }
                .frame(height: 50)
                .cornerRadius(Noora.CornerRadius.large)
                .signInWithAppleButtonStyle(colorScheme == .light ? .white : .black)
                .shadow(color: .black.opacity(0.05), radius: 0.5, x: 0, y: 1)
                .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
                .id(colorScheme)

                SocialButton(
                    title: "Sign in with Google",
                    style: .secondary,
                    icon: "GoogleLogo"
                ) {
                    errorHandling.fireAndHandleError { try await authenticationService.signInWithGoogle() }
                }

                SocialButton(
                    title: "Sign in with GitHub",
                    style: .secondary,
                    icon: "GitHubLogo"
                ) {
                    errorHandling.fireAndHandleError { try await authenticationService.signInWithGitHub() }
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
                .fill(.white.opacity(0.6))
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 32
                    )
                    .stroke(Color.white, lineWidth: 2)
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
