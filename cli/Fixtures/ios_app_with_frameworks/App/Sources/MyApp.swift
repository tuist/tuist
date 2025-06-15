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
        print("MyApp -> \(framework1.hello())")
        print("MyApp -> \(framework1.helloFromFramework2())")
        print("MyApp -> \(framework2.hello())")
        print("MyApp -> \(framework2Objc.hello())")
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
