// importing MyFramework would not work, because it is not linked
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        // let myFramework = MyFramework() // Things we can't do
        print("myFramework.hello()")
    }
}
