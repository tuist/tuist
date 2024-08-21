import SwiftUI

@main
struct TuistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Tuist", image: "MenuBarIcon") {
            MenuBarView(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}
