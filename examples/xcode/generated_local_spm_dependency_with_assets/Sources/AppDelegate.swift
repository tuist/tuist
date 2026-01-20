import LocalAssets
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let sampleText = LocalAssetsProvider.sampleText() {
            print(sampleText)
        }
        if let accentColor = LocalAssetsProvider.accentColor() {
            print(accentColor)
        }

        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }
}
