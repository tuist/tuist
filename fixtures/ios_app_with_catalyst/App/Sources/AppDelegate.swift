import SwiftUI
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.fixedCoordinateSpace.bounds)

        let viewController = UIHostingController(rootView: ContentView())
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }
}
