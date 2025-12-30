import Sentry
import SwiftUI

@main
struct MyApp: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

func startSentry() {
    SentrySDK.startSession()
}
