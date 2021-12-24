import Framework1
import StaticFramework
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let staticFrameworkResources = StaticFrameworkResources()

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("Main bundle image: \(String(describing: UIImage(named: "tuist")))")
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
