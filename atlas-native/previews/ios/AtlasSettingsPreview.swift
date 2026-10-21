import Foundation
import SwiftUI

@main
struct AtlasSettingsPreview: App {
    @State private var openedURL: URL?
    @StateObject private var holidays = AtlasTimeOffPreviewData()
    @StateObject private var business = AtlasBusinessPreviewData()
    @StateObject private var presence = AtlasPresencePreviewData()
    @StateObject private var appearance = AtlasAppearance(request: { action in
        if action["operation"] as? String == "themes" {
            if ProcessInfo.processInfo.arguments.contains("--old-server") { throw CancellationError() }
            let url = Bundle.main.url(forResource: "native_themes", withExtension: "json")!
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            return try await AtlasAppearance.bridge(["operation": "validate_themes", "catalog": catalog])
        }
        return try await AtlasAppearance.bridge(action)
    })
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
                    AtlasWorkspaceView(holidayRequest: holidays.request, businessRequest: business.request, presence: presence.model) {
                        AtlasSettingsView(server: URL(string: "https://atlas.example.org")!, accounts: accounts,
                                          signOut: {}, profileRequest: business.request)
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
            .modifier(AtlasThemeScope(appearance: appearance, server: URL(string: "https://atlas.example.org")))
            .task {
                await appearance.configure(server: URL(string: "https://atlas.example.org"))
                if !ProcessInfo.processInfo.arguments.contains("--keep-appearance") {
                    appearance.choose(theme: "server-default")
                    appearance.choose(mode: .system)
                }
            }
            .preferredColorScheme(appearance.mode.scheme ?? (ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light))
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility2 : .large)
        }
    }
}

@MainActor
private final class AtlasPresencePreviewData: ObservableObject {
    private var sequence = 0
    private var location: [String: String] = [:]
    private var waiting: CheckedContinuation<Data, Never>?
    lazy var model = AtlasPresence { [self] action in
        switch action["action"] as? String {
        case "open": return Data("{\"connection\":\"preview-only\"}".utf8)
        case "update":
            location = [:]
            for field in ["resource", "id"] {
                if let value = action[field] as? String { location[field] = value }
            }
            sequence += 1
            waiting?.resume(returning: snapshot())
            waiting = nil
            return Data("{\"updated\":true}".utf8)
        case "next":
            if (action["after"] as? UInt64 ?? 0) < sequence { return snapshot() }
            return await withCheckedContinuation { waiting = $0 }
        default:
            sequence += 1
            waiting?.resume(returning: snapshot())
            waiting = nil
            return Data("{\"closed\":true}".utf8)
        }
    }

    private func snapshot() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "sequence": sequence, "location": location,
            "people": [
                ["id": "online", "name": "Alex Morgan", "email": "alex@example.org", "online": true, "here": true],
                ["id": "offline", "name": "Sam Rivera", "email": "sam@example.org", "online": false, "here": false]
            ]
        ])
    }
}
