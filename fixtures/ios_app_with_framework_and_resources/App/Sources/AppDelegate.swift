import Framework1
import UIKit
import StaticFramework

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let staticFrameworkResources = StaticFrameworkResouces()
    
    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("Main bundle image: \(String(describing: UIImage(named: "tuist")))")
        print("StaticFrameworkResouce image: \(String(describing: staticFrameworkResources.tuist))")
    }
    

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
