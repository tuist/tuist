import StaticMetalFramework
import StaticResourcesFramework
import SwiftUI

@main
struct StaticFrameworkResourceTestsAndMetalApp: App {
    init() {
        _ = try? ResourceReader().message()
        _ = MetalStub().name
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
