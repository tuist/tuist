import Sparkle
import SwiftUI

@main
struct TuistApp: App {
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
