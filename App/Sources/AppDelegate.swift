import Cocoa
import Sparkle
import xcbuddykit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        UpdateController().checkAndUpdateFromApp(sender: self)
    }
}
