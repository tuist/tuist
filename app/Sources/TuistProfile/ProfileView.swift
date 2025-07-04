import SwiftUI
import TuistAuthentication
import TuistNoora

public struct ProfileView: View {
    @EnvironmentObject var authenticationService: AuthenticationService

    public init() {}

    public var body: some View {
        VStack(spacing: Noora.Spacing.spacing8) {
            Spacer()

            Circle()
                .fill(Noora.Colors.neutralLight300)
                .frame(width: 80, height: 80)
                .overlay(
                    Text("A")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                )

            VStack(spacing: Noora.Spacing.spacing2) {
                Text("Profile")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Noora.Colors.surfaceLabelPrimary)

                Text("Manage your account")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
            }

            Spacer()

            Button(
                "Log Out",
                action: {
                    Task {
                        await authenticationService.signOut()
                    }
                }
            )
            .padding(.horizontal, Noora.Spacing.spacing8)

            Spacer()
        }
        .background(Noora.Colors.surfaceBackgroundPrimary)
    }
}
