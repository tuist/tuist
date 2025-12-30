import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: NSView!

    override init() {
        super.init()

        let rect = NSRect(x: 0, y: 0, width: 500, height: 400)
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .white

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Window!"
    }

    func applicationDidFinishLaunching(_: Notification) {
        window.center()
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
    }
}
