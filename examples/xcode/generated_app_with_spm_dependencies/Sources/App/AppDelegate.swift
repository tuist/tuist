import AppKit
import CrashManager
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        let view = UIView(frame: CGRect(x: 10, y: 10, width: 300, height: 300))

        let imageView = UIImageView()
        imageView.contentMode = .center
        imageView.frame = CGRect(x: 10, y: 10, width: 50, height: 50)
        view.addSubview(imageView)

        let label = UILabel()
        label.numberOfLines = 0
        label.frame = CGRect(x: 10, y: 80, width: 200, height: 100)
        view.addSubview(label)

        let viewController = UIViewController()
        viewController.view.addSubview(view)

        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        CrashManager.start()
        AppKit.start()

        return true
    }
}
