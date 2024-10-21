import AppKit
import BrazeUI
import Styles
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        let view = UIView(frame: CGRect(x: 10, y: 10, width: 300, height: 300))
        view.backgroundColor = Styles.Color.yellow

        let imageView = UIImageView(image: StylesAsset.check.image)
        imageView.contentMode = .center
        imageView.frame = CGRect(x: 10, y: 10, width: 50, height: 50)
        view.addSubview(imageView)

        let label = UILabel()
        label.text = StylesStrings.greetingsText
        label.font = StylesFontFamily.Saira.regular.font(size: 14)
        label.numberOfLines = 0
        label.frame = CGRect(x: 10, y: 80, width: 200, height: 100)
        view.addSubview(label)

        let viewController = UIViewController(nibName: "ViewController", bundle: StylesResources.bundle)
        viewController.view.backgroundColor = Styles.Color.blue
        viewController.view.addSubview(view)

        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        let singleFile = StylesResources.bundle.url(forResource: "jsonFile", withExtension: "json")
        guard singleFile != nil else {
            fatalError("singleFile is missing")
        }

        let brazeUILocalizedString = BrazeUIResources.bundle?.localizedString(
            forKey: "braze.in-app-message.close-button.title",
            value: nil,
            table: "InAppMessageLocalizable"
        )
        precondition(brazeUILocalizedString == "Close", "Failed to fetch localized resource from BrazeUI")

        AppKit.start()

        return true
    }
}
