import UIKit
import Framework1
import Framework2

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func applicationDidFinishLaunching(_ application: UIApplication){

        let framework1 = Framework1File()
        let framework2 = Framework2File()

        print(hello())
        print("AppDelegate -> \(framework1.hello())")
        print("AppDelegate -> \(framework1.helloFromFramework2())")
        print("AppDelegate -> \(framework2.hello())")
    }

    func hello() -> String {
        return "AppDelegate.hello()"
    }
}
