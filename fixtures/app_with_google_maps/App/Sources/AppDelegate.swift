import DynamicFramework
import GoogleMaps
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
        let mapper = Mapper(frame: viewController.view.bounds)
        viewController.view.addSubview(mapper)
        mapper.mapView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [
                mapper.mapView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
                mapper.mapView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
                mapper.mapView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                mapper.mapView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            ]
        )

        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }
}
