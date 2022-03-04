import Framework1
import FrameworkA
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        print(hello())

        let framework1 = Framework1File()
        print("AppDelegate -> \(framework1.hello())")
        print("AppDelegate -> \(framework1.helloFromFramework2())")

        let frameworkA = FrameworkAFile()
        print("AppDelegate -> \(frameworkA.hello())")
        print("AppDelegate -> \(frameworkA.helloFromFrameworkB())")
        print("AppDelegate -> \(frameworkA.helloFromFrameworkC())")
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
