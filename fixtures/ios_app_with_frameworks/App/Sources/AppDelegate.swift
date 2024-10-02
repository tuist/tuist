import Framework1
import Framework2
import SwiftUI

@main
struct MyApp: SwiftUI.App {
    init() {
        let framework1 = Framework1File()
        let framework2 = Framework2File()
        let framework2Objc = MyPublicClass()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("AppDelegate -> \(framework1.helloFromFramework2())")
        print("AppDelegate -> \(framework2.hello())")
        print("AppDelegate -> \(framework2Objc.hello())")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
