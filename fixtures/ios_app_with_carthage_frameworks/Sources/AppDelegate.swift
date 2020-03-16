import UIKit
import RxSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func applicationDidFinishLaunching(_: UIApplication) {
        let observable = Observable<String>.just("hello world")
    }
    
    public func hello() -> String {
        return "AppDelegate.hello()"
    }
}
