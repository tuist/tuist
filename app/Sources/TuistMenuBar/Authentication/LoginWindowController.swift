import AppKit
import SwiftUI
import TuistAuthentication

@MainActor
final class LoginWindowController: NSWindowController {
    init(
        authenticationService: AuthenticationService,
        errorHandling: ErrorHandling
    ) {
        let contentView = MacLogInView()
            .environmentObject(authenticationService)
            .environmentObject(errorHandling)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Tuist"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 480, height: 680))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        authenticationService.setPresentationAnchor(window)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}
