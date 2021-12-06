import LibraryA
import PrebuiltStaticFramework
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        usePackageCode()
        useStaticLibraryCode()

        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }

    private func usePackageCode() {
        print(LibraryAClass().text)
    }

    private func useStaticLibraryCode() {
        let staticFrameworkClass = StaticFrameworkClass()
        print(staticFrameworkClass.hello())
    }
}
