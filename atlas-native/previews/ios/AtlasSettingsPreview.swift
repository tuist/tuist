import Foundation
import SwiftUI

@main
struct AtlasSettingsPreview: App {
    @State private var openedURL: URL?
    @StateObject private var holidays = AtlasTimeOffPreviewData()
    @StateObject private var accounts = AtlasAIAccounts { request in
        let response: String
        switch request["action"] as? String {
        case "list":
            response = """
            {"providers":[{"provider":"claude","credential_configured":false,"login_available":true},
            {"provider":"chatgpt","credential_configured":false,"login_available":true}]}
            """
        case "start_chatgpt":
            response = """
            {"login_id":"preview-only","user_code":"DEMO-CODE","verification_url":"https://auth.openai.com/codex/device",
            "interval":5,"expires_at":"2030-01-01T00:00:00Z"}
            """
        case "connect_claude":
            if ProcessInfo.processInfo.arguments.contains("--slow-save") {
                try await Task.sleep(for: .seconds(8))
            }
            response = "{}"
        case "cancel_chatgpt": response = "{\"status\":\"cancelled\"}"
        default: response = "{\"status\":\"pending\"}"
        }
        return Data(response.utf8)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--workspace") {
                    AtlasWorkspaceView(server: URL(string: "https://atlas.example.org")!, holidayRequest: holidays.request) {
                        AtlasSettingsView(server: URL(string: "https://atlas.example.org")!, accounts: accounts, signOut: {})
                    }
                } else {
                    NavigationStack {
                        if ProcessInfo.processInfo.arguments.contains("--time-off") {
                            AtlasTimeOffView(
                                title: AtlasCore.sections().first(where: { $0.screen == "time-off" })!.title,
                                request: holidays.request
                            )
                        } else {
                            AtlasSettingsView(server: URL(string: "https://atlas.example.org")!, accounts: accounts, signOut: {})
                        }
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                openedURL = url
                return .handled
            })
            .alert("Link preview", isPresented: Binding(
                get: { openedURL != nil }, set: { if !$0 { openedURL = nil } }
            )) {
                Button("Done", role: .cancel) { openedURL = nil }
            } message: {
                Text(openedURL?.absoluteString ?? "")
            }
            .tint(AtlasSettingsStyle.tint)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility2 : .large)
        }
    }
}
