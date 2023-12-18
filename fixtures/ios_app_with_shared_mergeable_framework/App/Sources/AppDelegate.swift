import MergeableXCFramework // XCFramework (dynamic framework)
import DynamicFrameworkA // Xcode target (dynamic framework)
import DynamicFrameworkB // Xcode target (dynamic framework)
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let mergeableXCFramework = MergeableXCFramework()
    private let dynamicFrameworkAComponent = DynamicFrameworkAComponent()
    private let dynamicFrameworkBComponent = DynamicFrameworkBComponent()

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .green
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        print(">> \(mergeableXCFramework.name)")
        print(">> \(dynamicFrameworkAComponent.composedName())")
        print(">> \(dynamicFrameworkBComponent.composedName())")

        return true
    }
}
