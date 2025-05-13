import AppKit
import Combine
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let onChangeOfURLs = PassthroughSubject<[URL], Never>()

    public func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURLs.send(urls)
    }
}
