import Framework1
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()
        let framework1Objc = MyPublicClass()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("AppDelegate -> \(framework1Objc.hello())")
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
