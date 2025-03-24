// importing MyFramework would not work, because it is not linked
import ThyFramework
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        // let myFramework = MyFramework() // Things we can't do
        let thyFramework = ThyFramework()
        print("myFramework.hello()")
        print(thyFramework.hello())
    }
}
