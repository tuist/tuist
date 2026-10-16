import AppKit
import Foundation
import Mockable

@Mockable
protocol MenuBarFocusServicing {
    /// Brings the application forward to display preview installation progress.
    func focus() async
}

struct MenuBarFocusService: MenuBarFocusServicing {
    func focus() async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
