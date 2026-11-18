import SwiftUI

/// One app for iOS and macOS. Only the Info.plist differs between the bundles.
@main
struct TuistGuildApp: App {
    // Delivers the APNs token and the notification tap that launched the app.
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #else
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    var body: some Scene {
        WindowGroup(id: WorkspaceCommands.window) {
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
        .commands { WorkspaceCommands() }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        #endif
    }
}
