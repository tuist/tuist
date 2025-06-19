import ModuleA
import SwiftUI

@main
struct TestApp: App {
    init() {
        ModuleA.test()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
