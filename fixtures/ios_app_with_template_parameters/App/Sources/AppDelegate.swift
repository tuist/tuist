import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()
        return true
    }

    func assertSynthesizedResources() {
        print("Files: \(try! MyFiles.loremTxt.url)")
        print("Assets: \(MyAssetsAsset.Assets.accentColor.name)")
        print("Plist: \(Options.someKey)")
        print("Font: \(MyFontsFontFamily.NotoSans.all.count)")
        print("Font: \(MyFontsFontFamily.NotoSansCondensed.all.count)")
        print("Font: \(MyFontsFontFamily.NotoSans.regular.name)")
        print("JSON: \(MyJSONFiles.Params.someString)")
        print("YAML: \(MyYAMLFiles.Settings.someString)")
        print("YAML: \(MyYAMLFiles.Settings.someBoolean)")
        print("YAML: \(MyYAMLFiles.Settings.someNumber)")
    }
}
