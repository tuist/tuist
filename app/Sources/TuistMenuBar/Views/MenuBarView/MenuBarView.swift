import Combine
import Foundation
import Sparkle
import SwiftUI
import TuistAuthentication
import TuistServer

public struct MenuBarView: View {
    @State var isExpanded = false
    @State var canCheckForUpdates = false
    @State private var isServerSettingsPresented = false
    private let errorHandling: ErrorHandling
    private let deviceService: DeviceService
    private let openLoginWindow: () -> Void
    @ObservedObject private var authenticationService: AuthenticationService
    @State var viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private let taskStatusReporter: TaskStatusReporter
    private let updater: SPUUpdater

    public init(
        appDelegate: AppDelegate,
        updaterController: SPUStandardUpdaterController
    ) {
        let authenticationService = appDelegate.authenticationService
        self.authenticationService = authenticationService
        openLoginWindow = { [weak appDelegate] in
            appDelegate?.presentLoginWindow()
        }
        let viewModel = MenuBarViewModel()
        self.viewModel = viewModel
        let taskStatusRepoter = TaskStatusReporter()
        taskStatusReporter = taskStatusRepoter

        let deviceService = DeviceService(
            taskStatusReporter: taskStatusRepoter
        )
        self.deviceService = deviceService

        let credentialsStore = appDelegate.credentialsStore
        let errorHandling = appDelegate.errorHandling
        self.errorHandling = errorHandling

        // We can't rely on SwiftUI views to be rendered before a deeplink is triggered.
        // Instead, we listen to the deeplink URL through an `AppDelegate` callback
        // that's eagerly set up in this `init` on startup.
        appDelegate.onChangeOfURLs.sink { urls in
            guard let url = urls.first else { return }
            let serverURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "server_url" })?
                .value
                .flatMap { URL(string: $0) }
            Task {
                do {
                    try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                        try await deviceService.launchPreviewDeeplink(with: url)
                    }
                } catch {
                    errorHandling.handle(error: error, serverURL: serverURL)
                }
            }
        }
        .store(in: &cancellables)

        Task {
            do {
                try await deviceService.loadDevices()
            } catch {
                errorHandling.handle(error: error)
            }
        }

        updater = updaterController.updater

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink {
                viewModel.canCheckForUpdatesValueChanged($0)
            }
            .store(in: &cancellables)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch authenticationService.authenticationState {
            case let .loggedIn(account, serverURL):
                MenuHeader(
                    accountHandle: account.handle
                )

                AppPreviews(
                    viewModel: AppPreviewsViewModel(
                        deviceService: deviceService
                    )
                )
                .id(serverURL)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 8)

                DevicesView(
                    viewModel: DevicesViewModel(deviceService: deviceService)
                )
            case .loggedOut:
                MenuBarLoginView(openLoginWindow: openLoginWindow)
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Group {
                if authenticationService.authenticationState != .loggedOut {
                    Button("Log out") {
                        errorHandling.fireAndHandleError {
                            await authenticationService.signOut()
                        }
                    }
                    .padding(.vertical, 2)
                    .menuItemStyle()
                    .padding(.horizontal, 8)
                }

                Button("Server: \(serverDisplayName)") {
                    isServerSettingsPresented = true
                }
                .padding(.vertical, 2)
                .menuItemStyle()
                .padding(.horizontal, 8)

                Button("Check for updates", action: {
                    updater.checkForUpdates()
                })
                .disabled(!viewModel.canCheckForUpdates)
                .padding(.vertical, 2)
                .menuItemStyle()
                .padding(.horizontal, 8)

                Button("Quit Tuist") {
                    NSApplication.shared.terminate(nil)
                }
                .padding(.vertical, 2)
                .menuItemStyle()
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 8)
        .environmentObject(errorHandling)
        .environmentObject(deviceService)
        .environmentObject(taskStatusReporter)
        .environmentObject(authenticationService)
        .sheet(isPresented: $isServerSettingsPresented) {
            ServerSettingsView(authenticationService: authenticationService)
        }
    }

    private var serverDisplayName: String {
        guard let host = authenticationService.serverURL.host() else {
            return authenticationService.serverURL.absoluteString
        }
        if let port = authenticationService.serverURL.port {
            return "\(host):\(port)"
        }
        return host
    }
}
