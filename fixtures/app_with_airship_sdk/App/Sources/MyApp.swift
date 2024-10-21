import AirshipPreferenceCenter
import SwiftUI

@main
struct MyApp: App {
    init() {
        _ = AirshipPreferenceCenter.ErrorLabel(message: "Message", theme: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
