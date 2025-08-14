import Framework1
import SwiftUI

@main
struct MyApp: SwiftUI.App {
    init() {
        let framework1 = Framework1File()

        print(hello())
        print("MyApp -> \(framework1.hello())")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    func hello() -> String {
        "MyApp.hello()"
    }
}
