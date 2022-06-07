import Framework1
import Framework2
import MyLogger
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()
        let framework2 = Framework2File()

        let logger = MyLogger()
        logger.log(hello())

        logger.log("AppDelegate -> \(framework1.hello())")
        logger.log("AppDelegate -> \(framework1.helloFromFramework2())")
        logger.log("AppDelegate -> \(framework2.hello())")
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
