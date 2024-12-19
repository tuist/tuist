import Combine
import Foundation
import Sparkle
import SwiftUI

struct MenuBarView: View {
    @State var isExpanded = false
    @State var canCheckForUpdates = false
    private let errorHandling: ErrorHandling
    private let deviceService: DeviceService
    @EnvironmentObject
    private var appCredentialsService: AppCredentialsService
    @State var viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private let taskStatusReporter: TaskStatusReporter
    private let updater: SPUUpdater

    init(
        appDelegate: AppDelegate,
        updaterController: SPUStandardUpdaterController
    ) {
        let viewModel = MenuBarViewModel()
        self.viewModel = viewModel
        let taskStatusRepoter = TaskStatusReporter()
        taskStatusReporter = taskStatusRepoter

        let deviceService = DeviceService(
            taskStatusReporter: taskStatusRepoter
        )
        self.deviceService = deviceService

        let errorHandling = ErrorHandling()
        self.errorHandling = errorHandling

        // We can't rely on SwiftUI views to be rendered before a deeplink is triggered.
        // Instead, we listen to the deeplink URL through an `AppDelegate` callback
        // that's eagerly set up in this `init` on startup.
        appDelegate.onChangeOfURLs.sink { urls in
            guard let url = urls.first else { return }
            Task {
                do {
                    try await deviceService.launchPreviewDeeplink(with: url)
                } catch {
                    errorHandling.handle(error: error)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeader(
                accountHandle: appCredentialsService.accountHandle
            )

            AppPreviews(
                viewModel: AppPreviewsViewModel(
                    appCredentialsService: appCredentialsService,
                    deviceService: deviceService
                )
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 12)

            DevicesView(
                viewModel: DevicesViewModel(deviceService: deviceService)
            )

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Group {
                switch appCredentialsService.authenticationState {
                case .loggedIn:
                    Button("Log out") {
                        errorHandling.fireAndHandleError(appCredentialsService.logout)
                    }
                case .loggedOut:
                    Button("Log in") {
                        errorHandling.fireAndHandleError(appCredentialsService.login)
                    }
                }
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
        .padding(.vertical, 8)
        .environmentObject(errorHandling)
        .environmentObject(deviceService)
        .environmentObject(taskStatusReporter)
        .onAppear {
            appCredentialsService.loadCredentials()
            errorHandling.fireAndHandleError(appCredentialsService.updateAuthenticationState)
        }
    }
}
