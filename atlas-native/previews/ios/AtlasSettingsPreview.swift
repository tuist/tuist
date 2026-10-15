import Foundation
import SwiftUI

@main
struct AtlasSettingsPreview: App {
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
        case "cancel_chatgpt": response = "{\"status\":\"cancelled\"}"
        default: response = "{\"status\":\"pending\"}"
        }
        return Data(response.utf8)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                AtlasSettingsView(server: URL(string: "https://atlas.example.org")!, accounts: accounts, signOut: {})
            }
            .tint(AtlasBrand.accent)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility2 : .large)
        }
    }
}
