import AppKit
import Combine
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let onChangeOfURLs = PassthroughSubject<[URL], Never>()

    func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURLs.send(urls)
    }
}
