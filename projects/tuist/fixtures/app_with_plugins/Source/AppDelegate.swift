import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        print(Strings.hello)
        #if canImport(Lottie)
            print(AnimationAsset.allAnimations.everythingBagel)
        #endif

        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        viewController.view.addSubview(TestView())
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }
}
