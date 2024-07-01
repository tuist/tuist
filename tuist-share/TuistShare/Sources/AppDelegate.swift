import Foundation
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var url: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        url = urls.first
    }
}
