import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        print(hello())
    }

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
