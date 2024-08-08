import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}


@main
struct TuistShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra("Tuist", image: "MenuBarIcon") {
            MenuBarView(
                appDelegate: appDelegate,
                updaterController: updaterController
            )
        }
        .menuBarExtraStyle(.window)
    }
}
