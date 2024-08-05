import DynamicFramework
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        Mapper.provide(key: "key_not_need_to_see_bundle_missing_crash")

        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.addSubview(Mapper(frame: viewController.view.bounds))
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }
}
