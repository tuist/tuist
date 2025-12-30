import AppKit
import Combine
import FluidMenuBarExtra
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    public var menuBarExtra: FluidMenuBarExtra?

    let onChangeOfURLs = PassthroughSubject<[URL], Never>()

    public func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURLs.send(urls)
    }
}
