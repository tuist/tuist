import Foundation
import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora
import TuistServer

public struct ProfileView: View {
    @EnvironmentObject private var errorHandler: ErrorHandling
    @EnvironmentObject private var authenticationService: AuthenticationService
    private let deleteAccountService: DeleteAccountServicing = DeleteAccountService()

    private let account: Account

    public init(
        account: Account
    ) {
        self.account = account
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    NooraAvatar(email: account.email, size: .xxlarge)

                    Text("@\(account.handle)")
                        .font(.body.weight(.medium))
                        .fontWeight(.medium)
                        .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                HStack {
                    Text("Email")
                        .font(.body)
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                    Spacer()
                    Text(account.email)
                        .font(.body)
                        .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                }
            }

            Section {
                ExternalLinkRow(
                    title: "Terms of Service",
                    url: URL(string: "https://tuist.dev/terms")!
                )
                ExternalLinkRow(
                    title: "Privacy Policy",
                    url: URL(string: "https://tuist.dev/privacy")!
                )
            }

            Section {
                ExternalLinkRow(
                    title: "Get help",
                    url: URL(string: "mailto:contact@tuist.dev")!
                )
            }

            Section {
                HStack {
                    Text("App version")
                        .font(.body)
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                    Spacer()
                    Text("1.0.0")
                        .font(.body)
                        .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                }
            }

            Section {
                Button(action: {
                    Task {
                        await authenticationService.signOut()
                    }
                }) {
                    Text("Sign out")
                        .font(.body)
                        .foregroundColor(Noora.Colors.accent)
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                Button(action: {
                    errorHandler.fireAndHandleError {
                        try await authenticationService.deleteAccount(account)
                    }
                }) {
                    Text("Delete account")
                        .font(.body)
                        .foregroundColor(Noora.Colors.surfaceLabelDestructive)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Noora.Colors.surfaceBackgroundPrimary)
    }
}
