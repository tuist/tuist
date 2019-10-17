import A
import C
import UIKit
import PrebuiltStaticFramework

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        A.printFromA()
        C.printFromC()
        
        let staticFrameworkClass = StaticFrameworkClass()
        print(staticFrameworkClass.hello())

        return true
    }
}

public class AClassInThisBundle {
    public static let value: String = "aValue"
}
