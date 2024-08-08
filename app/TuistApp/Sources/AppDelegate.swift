import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var onChangeOfURL: ((URL?) -> Void)?

    func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURL?(urls.first)
    }
}
