import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        guard let bundle = Bundle(path: "\(Bundle.main.bundlePath)/Dbundle.bundle"),
              bundle.load()
        else {
            fatalError(
                "Cannot load bundle"
            )
        }

        let className = "Dload.DloadFramework"
        guard let viewClass = NSClassFromString(className) as? UIView.Type else {
            fatalError("Cannot load view controller with name \(className)")
        }

        let view = viewClass.init()

        return true
    }
}
