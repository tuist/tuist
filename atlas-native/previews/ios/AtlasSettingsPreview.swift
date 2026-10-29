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
    @StateObject private var environments = AtlasEnvironmentPreviewData()
    @StateObject private var presence = AtlasPresencePreviewData()
    @StateObject private var navigation = AtlasNavigation()
    @StateObject private var notifications = AtlasPushNotifications()
    @StateObject private var connections = AtlasConnections(request: { action in
        if action["action"] as? String == "list" {
            let configured = !ProcessInfo.processInfo.arguments.contains("--unavailable-connections")
            return Data("""
            {"connections":[{"provider":"github","name":"GitHub","configured":\(configured),
            "account_name":null,"status":"not_connected"},
            {"provider":"slack","name":"Slack","configured":\(configured),
            "account_name":\(configured ? "\"Demo teammate · Demo workspace\"" : "null"),
            "status":"\(configured ? "connected" : "not_connected")"},
            {"provider":"google","name":"Google","configured":true,
            "account_name":"demo@example.org","status":"needs_authorization"}]}
            """.utf8)
        }
        throw AtlasAuthenticationError(kind: "preview", message: "Preview only. No accounts are changed.")
    }, authorize: { _ in nil })
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
                if ProcessInfo.processInfo.arguments.contains("--coding") {
                    NavigationStack { AtlasCodingSettingsView(request: environments.request) }
                } else if ProcessInfo.processInfo.arguments.contains("--repository-picker") {
                    AtlasThreadRepositoryPicker(threadId: "00000000-0000-4000-8000-000000000001", selected: "acme/mobile",
                                                request: environments.request, changed: {})
                } else if ProcessInfo.processInfo.arguments.contains("--live-activity") {
                    AtlasLiveActivityPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--voice-input") {
                    AtlasVoiceInputPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--notification-settings") {
                    NavigationStack {
                        Form {
                            Section { Text("Preview only. Device registration is disabled.") }
                            AtlasPushSettingsView(notifications: notifications).disabled(true)
                        }.navigationTitle("Notifications")
                    }
                } else if ProcessInfo.processInfo.arguments.contains("--workspace") {
                    AtlasWorkspaceView(holidayRequest: holidays.request, businessRequest: business.request,
                                       orbitRequest: threads.request, orbitLocalRequest: threads.local, presence: presence.model,
                                       navigation: navigation) {
                        AtlasSettingsView(server: previewServer, accounts: accounts,
                                          signOut: {}, profileRequest: business.request, connections: connections)
                    }
                } else {
                    NavigationStack {
                        if ProcessInfo.processInfo.arguments.contains("--connections") {
                            AtlasConnectionsView(model: connections)
                        } else if ProcessInfo.processInfo.arguments.contains("--time-off") {
                            AtlasTimeOffView(
                                title: AtlasCore.sections().first(where: { $0.screen == "time-off" })!.title,
                                request: holidays.request
                            )
                        } else {
                            AtlasSettingsView(server: previewServer, accounts: accounts, signOut: {}, connections: connections)
                        }
                    }
                }
            }
            .environment(\.atlasNavigation, navigation)
            .environment(\.atlasServer, previewServer)
            .environment(\.atlasEnvironmentRequest, environments.request)
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
            .environment(\._accessibilityReduceTransparency, ProcessInfo.processInfo.arguments.contains("--reduce-transparency"))
            .environment(\._colorSchemeContrast, ProcessInfo.processInfo.arguments.contains("--increased-contrast") ? .increased : .standard)
        }
    }
}
