import Foundation
import SwiftUI

@main
struct AtlasSettingsPreview: App {
    @State private var openedURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgrounded = false
    @StateObject private var holidays = AtlasTimeOffPreviewData()
    @StateObject private var business = AtlasBusinessPreviewData()
    @StateObject private var presence = AtlasPresencePreviewData()
    @StateObject private var navigation = AtlasNavigation()
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
                    AtlasWorkspaceView(holidayRequest: holidays.request, businessRequest: business.request, presence: presence.model,
                                       navigation: navigation) {
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
            .environment(\.atlasNavigation, navigation)
            .environment(\.atlasServer, URL(string: "https://atlas.example.org")!)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { backgrounded = true }
                if phase == .active, backgrounded {
                    backgrounded = false
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "--resume-destination"), arguments.indices.contains(index + 1),
                       let url = URL(string: arguments[index + 1]) {
                        navigation.receive(url, server: URL(string: "https://atlas.example.org")!)
                    }
                }
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--destination"), arguments.indices.contains(index + 1),
                   let url = URL(string: arguments[index + 1]) {
                    navigation.receive(url, server: URL(string: "https://atlas.example.org")!)
                }
            }
            .alert("Atlas link", isPresented: Binding(
                get: { navigation.message != nil && !navigation.hasVisibleProtectedWork },
                set: { if !$0 { navigation.message = nil } }
            )) {
                Button("OK") { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
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
