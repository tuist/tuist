import AppKit
import Foundation
import Mockable

@Mockable
protocol MenuBarFocusServicing {
    /// Focus on the menu bar window, in other words, it puts the menu bar window to the foreground
    func focus() async
}

struct MenuBarFocusService: MenuBarFocusServicing {
    func focus() async {
        let statusItem = await NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
        await statusItem?.button?.performClick(nil)
    }
}
