import LocalLib
import SwiftUI

@main
struct AppApp: App {
    let lib = LocalLib()

    var body: some Scene {
        WindowGroup {
            Text("Hello, World!")
        }
    }
}
