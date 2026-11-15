import SwiftUI

/// One app for iOS and macOS. Only the Info.plist differs between the bundles.
@main
struct TuistCodeApp: App {
    var body: some Scene {
        WindowGroup {
            AppWorkspace()
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        #endif
    }
}
