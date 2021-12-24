import Framework1
import Framework2
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()
        let framework2 = Framework2File()
        let framework2Objc = MyPublicClass()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("AppDelegate -> \(framework1.helloFromFramework2())")
        print("AppDelegate -> \(framework2.hello())")
        print("AppDelegate -> \(framework2Objc.hello())")
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
