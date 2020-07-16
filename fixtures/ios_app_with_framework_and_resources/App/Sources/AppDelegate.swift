import Framework1
import UIKit
import StaticFramework
import StaticFramework2
import StaticFramework3

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let staticFrameworkResources = StaticFrameworkResouces()
    let staticFramework2Resources = StaticFramework2Resources()
    let staticFramework3Resources = StaticFramework3Resources()
    
    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("Main bundle image: \(String(describing: UIImage(named: "tuist")))")
        print("StaticFrameworkResouce image: \(String(describing: staticFrameworkResources.tuist))")
        print("StaticFramework2Resouce image: \(String(describing: staticFramework2Resources.loadImage()))")
        print("StaticFramework3Resouce image: \(String(describing: staticFramework3Resources.loadImage()))")
    }
    

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
