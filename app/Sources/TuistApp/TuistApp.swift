import SwiftUI

#if canImport(TuistMenuBar)
    import Sparkle
    import TuistMenuBar

    @main
    struct TuistApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

        private let updaterController: SPUStandardUpdaterController
        private let appCredentialsService = AppCredentialsService()

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
                .environmentObject(appCredentialsService)
            }
            .menuBarExtraStyle(.window)
        }
    }
#else
    @main
    struct TuistApp: App {
        var body: some Scene {
            WindowGroup {
                Text("Tuist app")
            }
        }
    }
#endif
