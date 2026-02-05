import ModuleA
import ModuleB
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let classA = ClassA()
        let classB = ClassB()
        let swiftA = ModuleAFile()
        let swiftB = ModuleBFile()

        print("AppDelegate -> \(classA.hello())")
        print("AppDelegate -> \(classB.hello())")
        print("AppDelegate -> \(swiftA.hello())")
        print("AppDelegate -> \(swiftB.hello())")

        return true
    }
}
