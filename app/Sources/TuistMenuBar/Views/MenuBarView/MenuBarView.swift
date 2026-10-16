import AppKit
import SwiftUI
import TuistAuthentication

public struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var applicationModel: MacApplicationModel
    @ObservedObject private var authenticationService: AuthenticationService

    public init(applicationModel: MacApplicationModel) {
        self.applicationModel = applicationModel
        authenticationService = applicationModel.authenticationService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Open Tuist") {
                openWindow(id: DesktopWindow(authenticationState: authenticationService.authenticationState).rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            .menuItemStyle()
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            switch authenticationService.authenticationState {
            case let .loggedIn(account, _):
                MenuHeader(accountHandle: account.handle)

                AppPreviews(viewModel: AppPreviewsViewModel(deviceService: applicationModel.deviceService))
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                DevicesView(viewModel: DevicesViewModel(deviceService: applicationModel.deviceService))
            case .loggedOut:
                Button("Sign In…") {
                    openWindow(id: DesktopWindow.welcome.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .menuItemStyle()
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Group {
                SettingsLink {
                    Text("Settings…")
                }
                .buttonStyle(.plain)
                .menuItemStyle()

                Button("Check for Updates…") {
                    applicationModel.checkForUpdates()
                }
                .disabled(!applicationModel.canCheckForUpdates)
                .menuItemStyle()

                if authenticationService.authenticationState != .loggedOut {
                    Button("Sign Out") {
                        applicationModel.errorHandling.fireAndHandleError {
                            await authenticationService.signOut()
                        }
                    }
                    .menuItemStyle()
                }

                Button("Quit Tuist") {
                    NSApplication.shared.terminate(nil)
                }
                .menuItemStyle()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 300)
        .macApplicationEnvironment(applicationModel)
        .task {
            do {
                try await applicationModel.loadDevices()
            } catch {
                applicationModel.errorHandling.handle(error: error)
            }
        }
    }
}
