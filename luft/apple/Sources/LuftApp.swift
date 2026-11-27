import SwiftUI

/// One app for iOS and macOS. Only the Info.plist differs between the bundles.
@main
struct LuftApp: App {
    // Delivers the APNs token and the notification tap that launched the app.
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #else
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    /// One client for the window and, on the Mac, Settings, which registers runners.
    @State private var client = AppClient.shared

    var body: some Scene {
        WindowGroup(id: WorkspaceCommands.window) {
            #if targetEnvironment(simulator)
                if WorkspacePreview.requested {
                    WorkspacePreview()
                } else if ProcessInfo.processInfo.arguments.contains("-LuftToolPreview") {
                    ToolPreview()
                } else if ProcessInfo.processInfo.arguments.contains("-LuftCardPreview") ||
                    ProcessInfo.processInfo.arguments.contains("-LuftDecisionPreview")
                {
                    CardPreview()
                } else if ProcessInfo.processInfo.arguments.contains("-LuftSandboxPreview") {
                    SandboxReadyPreview()
                } else {
                    AppWorkspace(client: client)
                }
            #elseif os(macOS)
                if ProcessInfo.processInfo.arguments.contains("-LuftCardPreview") ||
                    ProcessInfo.processInfo.arguments.contains("-LuftDecisionPreview")
                {
                    CardPreview()
                } else {
                    AppWorkspace(client: client)
                }
            #else
                AppWorkspace(client: client)
            #endif
        }
        .commands { WorkspaceCommands() }
        #if os(macOS)
            .defaultSize(width: 960, height: 640)
        #endif
        #if os(macOS)
            // Luft ▸ Settings… (⌘,): runs threads on this Mac.
            Settings { SettingsView(client: client) }
                // The window follows the pane: short until the runner is installed.
                .windowResizability(.contentSize)
        #endif
    }
}
