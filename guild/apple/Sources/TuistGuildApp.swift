import SwiftUI

/// One app for iOS and macOS. Only the Info.plist differs between the bundles.
@main
struct TuistGuildApp: App {
    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-GuildCardPreview") {
                    CardPreview()
                } else {
                    AppWorkspace()
                }
            #else
                AppWorkspace()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        #endif
    }
}
