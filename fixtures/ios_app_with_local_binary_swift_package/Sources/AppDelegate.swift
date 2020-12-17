import UIKit
import MyFramework

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    let myFrameworkClass = MyFrameworkClass()
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        print(myFrameworkClass.name)

        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }

}
