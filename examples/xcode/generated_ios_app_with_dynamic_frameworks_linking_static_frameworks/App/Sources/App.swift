import DynamicFrameworkA
import SwiftUI

@main
struct MyApp: App {
    private var dynamicFramework = DynamicFrameworkA()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
