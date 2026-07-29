import FirebaseMLModelDownloader
import GEOSwift
import Gzip
import LocalModuleMap
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        _ = local_module_map_answer()
        return true
    }
}
