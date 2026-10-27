import SwiftUI
import Framework1

@main
struct AppApp: App {
    var body: some Scene {
        WindowGroup {
            Text(Framework1File().greeting())
        }
    }
}
