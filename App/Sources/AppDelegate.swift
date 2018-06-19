import Cocoa
import xpmKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        UpdateController().checkAndUpdateFromApp(sender: self)
    }
}
