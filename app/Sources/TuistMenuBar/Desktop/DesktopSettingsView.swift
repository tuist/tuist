import SwiftUI
import TuistAuthentication

public struct DesktopSettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @ObservedObject private var applicationModel: MacApplicationModel
    @ObservedObject private var authenticationService: AuthenticationService

    public init(applicationModel: MacApplicationModel) {
        self.applicationModel = applicationModel
        authenticationService = applicationModel.authenticationService
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Show Tuist in the menu bar", isOn: $showMenuBarExtra)
                Text("Keep recent previews and devices a click away, even when the main window is closed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Account") {
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
                    Text("Sign in from the main window to access your projects and previews.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                )
                Button("Check for Updates…") { applicationModel.checkForUpdates() }
                    .disabled(!applicationModel.canCheckForUpdates)
                Link("Tuist Documentation", destination: URL(string: "https://docs.tuist.dev")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 460)
    }
}
