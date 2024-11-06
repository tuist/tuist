import Combine
import Foundation
import Sparkle
import SwiftUI

struct MenuBarView: View {
    @State var isExpanded = false
    private let errorHandling: ErrorHandling
    private let deviceService: DeviceService
    private let viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()

    init(
        appDelegate: AppDelegate,
        updaterController: SPUStandardUpdaterController
    ) {
        viewModel = MenuBarViewModel(
            updater: updaterController.updater
        )
        let deviceService = DeviceService()
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tuist")
                .font(.headline)
                .fontWeight(.medium)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .padding(.horizontal, 8)

            AppPreviews(
                viewModel: AppPreviewsViewModel(deviceService: deviceService)
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

            Button("Check for updates", action: viewModel.checkForUpdates)
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
    }
}
