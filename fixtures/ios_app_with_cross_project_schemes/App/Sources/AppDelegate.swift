import Framework
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework = Framework()

        print(hello())
        print("AppDelegate -> \(framework.hello())")
    }

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
