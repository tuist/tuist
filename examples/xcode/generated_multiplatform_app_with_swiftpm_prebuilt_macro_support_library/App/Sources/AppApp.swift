import Formatting
import Highlighting
import SwiftUI

@main
struct AppApp: App {
    var body: some Scene {
        WindowGroup {
            Text("\(formattedMessage) \(highlightedMessage)")
        }
    }
}
