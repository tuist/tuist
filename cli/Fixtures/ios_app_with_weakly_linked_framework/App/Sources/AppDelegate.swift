import MyFramework
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let myFramework = MyFramework()
        print(myFramework.hello())
    }
}
