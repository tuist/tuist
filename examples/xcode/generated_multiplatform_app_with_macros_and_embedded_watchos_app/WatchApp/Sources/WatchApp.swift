import CasePaths
import ModuleA
import SwiftUI

@CasePathable
enum WatchAppAction {
    case home
}

@main
struct WatchApp: App {
    init() {
        ModuleA.test()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
