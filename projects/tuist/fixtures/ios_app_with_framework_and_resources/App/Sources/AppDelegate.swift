import Framework1
import StaticFramework
import StaticFramework2
import StaticFramework3
import StaticFramework4
import StaticFramework5
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let staticFrameworkResources = StaticFrameworkResources()
    let staticFramework2Resources = StaticFramework2Resources()
    let resourcesStaticFramework3 = ResourcesStaticFramework3()
    let resourcesStaticFramework4 = ResourcesStaticFramework4()

    func applicationDidFinishLaunching(_: UIApplication) {
        let framework1 = Framework1File()

        print(hello())
        print("Custom plist: \(Environment.myKey)")
        print("Another custom plist: \(AnotherPlist.myKey)")
        print("AppDelegate -> \(framework1.hello())")
        print("Main bundle image: \(String(describing: UIImage(named: "tuist")))")
        print("Asset catalogue image: \(String(describing: AppAsset.assetCatalogLogo.image))")
        print("Strings: \(AppStrings.Greetings.morning)")
        print("String dicts: \(AppStrings.App.appleCount(1))")
        print("Font: \(AppFontFamily.SFProDisplay.bold.name)")
        print("StaticFrameworkResource image: \(String(describing: staticFrameworkResources.tuist))")
        print("StaticFramework2Resource image: \(String(describing: staticFramework2Resources.loadImage()))")
        print("StaticFramework3Resource image: \(String(describing: resourcesStaticFramework3.loadImage()))")
        print(
            "StaticFramework3Resource asset catalogue image: \(String(describing: StaticFramework3Asset.assetCatalogLogo.image))"
        )
        print("StaticFramework4Resource image: \(String(describing: resourcesStaticFramework4.loadImage()))")
        print(
            "StaticFramework5Resource image: \(String(describing: UIImage(named: "StaticFramework5Resources-tuist", in: StaticFramework5Resources.bundle, compatibleWith: nil)))"
        )
    }

    func hello() -> String {
        "AppDelegate.hello()"
    }
}
