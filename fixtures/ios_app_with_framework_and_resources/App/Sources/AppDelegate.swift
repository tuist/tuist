import Framework1
import UIKit
import StaticFramework
import StaticFramework2
import StaticFramework3
import StaticFramework4
import StaticFramework5

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let staticFrameworkResources = StaticFrameworkResouces()
    let staticFramework2Resources = StaticFramework2Resources()
    let resourcesStaticFramework3 = ResourcesStaticFramework3()
    let resourcesStaticFramework4 = ResourcesStaticFramework4()

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("Main bundle image: \(String(describing: UIImage(named: "tuist")))")
        print("StaticFrameworkResource image: \(String(describing: staticFrameworkResources.tuist))")
        print("StaticFramework2Resource image: \(String(describing: staticFramework2Resources.loadImage()))")
        print("StaticFramework3Resource image: \(String(describing: resourcesStaticFramework3.loadImage()))")
        print("StaticFramework4Resource image: \(String(describing: resourcesStaticFramework4.loadImage()))")
        print("StaticFramework5Resource image: \(String(describing: UIImage(named:"StaticFramework5Resources-tuist", in: StaticFramework5Resources.bundle, compatibleWith: nil)))")
    }
    

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
