import A
import C
import PrebuiltStaticFramework
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()

        A.printFromA()
        C.printFromC()

        let staticFrameworkClass = StaticFrameworkClass()
        print(staticFrameworkClass.hello())

        return true
    }
}

public enum AClassInThisBundle {
    public static let value: String = "aValue"
}
