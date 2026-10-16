import SwiftUI
import TuistAuthentication

public struct DesktopSettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @ObservedObject private var applicationModel: MacApplicationModel
    @ObservedObject private var authenticationService: AuthenticationService

    public init(applicationModel: MacApplicationModel) {
        self.applicationModel = applicationModel
        authenticationService = applicationModel.authenticationService
    }

    public var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            account
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 500, height: 340)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Show Tuist in the menu bar", isOn: $showMenuBarExtra)
            } footer: {
                Text("Keep recent previews and devices a click away, even when the main window is closed.")
            }
            Section("Updates") {
                Button("Check for Updates…") { applicationModel.checkForUpdates() }
                    .disabled(!applicationModel.canCheckForUpdates)
            }
            Section {
                Link("Tuist Documentation", destination: URL(string: "https://docs.tuist.dev")!)
            }
        }
        .formStyle(.grouped)
    }

    private var account: some View {
        Form {
            Section {
                switch authenticationService.authenticationState {
                case let .loggedIn(account, _):
                    LabeledContent("Account", value: account.handle)
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Server", value: AppServerEnvironmentService().url().absoluteString)
                    Button("Sign Out") {
                        applicationModel.errorHandling.fireAndHandleError {
                            await authenticationService.signOut()
                        }
                    }
                case .loggedOut:
                    Text("Sign in from the welcome window to access your projects and previews.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
