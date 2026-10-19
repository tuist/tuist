import AppKit
import Combine
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    public var openMainWindow: (() -> Void)?

    let onChangeOfURLs = PassthroughSubject<[URL], Never>()

    public func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURLs.send(urls)
    }

    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            openMainWindow?()
        }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
