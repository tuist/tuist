import Foundation
import SwiftUI

@main
struct AtlasSettingsPreview: App {
    @State private var openedURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgrounded = false
    @StateObject private var holidays = AtlasTimeOffPreviewData()
    @StateObject private var business = AtlasBusinessPreviewData()
    @StateObject private var threads = AtlasOrbitPreviewData()
    @StateObject private var presence = AtlasPresencePreviewData()
    @StateObject private var navigation = AtlasNavigation()
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

    private var previewServer: URL {
        URL(string: ProcessInfo.processInfo.arguments.contains("--old-server")
            ? "https://legacy.example.org" : "https://atlas.example.org")!
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--voice-input") {
                    AtlasVoiceInputPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--workspace") {
                    AtlasWorkspaceView(holidayRequest: holidays.request, businessRequest: business.request,
                                       orbitRequest: threads.request, orbitLocalRequest: threads.local, presence: presence.model,
                                       navigation: navigation) {
                        AtlasSettingsView(server: previewServer, accounts: accounts,
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
                            AtlasSettingsView(server: previewServer, accounts: accounts, signOut: {})
                        }
                    }
                }
            }
            .environment(\.atlasNavigation, navigation)
            .environment(\.atlasServer, previewServer)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { backgrounded = true }
                if phase == .active, backgrounded {
                    backgrounded = false
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "--resume-destination"), arguments.indices.contains(index + 1),
                       let url = URL(string: arguments[index + 1]) {
                        navigation.receive(url, server: previewServer)
                    }
                }
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--destination"), arguments.indices.contains(index + 1),
                   let url = URL(string: arguments[index + 1]) {
                    navigation.receive(url, server: previewServer)
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
            .modifier(AtlasThemeScope(appearance: appearance, server: previewServer))
            .task {
                await appearance.configure(server: previewServer)
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
            "sequence": sequence, "location": location, "self_id": "preview-self",
            "people": [
                ["id": "online", "name": "Alex Morgan", "email": "alex@example.org", "online": true,
                 "here": !location.isEmpty && !ProcessInfo.processInfo.arguments.contains("--nobody-here")],
                ["id": "offline", "name": "Sam Rivera", "email": "sam@example.org", "online": false, "here": false]
            ]
        ])
    }
}
