import MyFramework // XCFramework (dynamic framework)
import StaticFrameworkA // Xcode target (static framework)
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let myFramework = MyFramework()
    private let staticFrameworkAComponent = StaticFrameworkAComponent()

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        print(">> \(myFramework.name)")
        print(">> \(staticFrameworkAComponent.composedName())")

        return true
    }
}
