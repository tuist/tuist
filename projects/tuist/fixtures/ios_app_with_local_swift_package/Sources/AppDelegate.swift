import FrameworkA
import LibraryA
import LibraryB
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        useFrameworkCode()
        usePackageCode()

        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }

    private func useFrameworkCode() {
        print(FrameworkAClass().text)
    }

    private func usePackageCode() {
        print(LibraryAClass().text)
        print(LibraryBClass().text)
    }
}
