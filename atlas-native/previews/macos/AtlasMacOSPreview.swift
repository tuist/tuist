import SwiftUI

@main
struct AtlasMacOSPreview: App {
    @StateObject private var holidays = AtlasTimeOffPreviewData()
    @StateObject private var business = AtlasBusinessPreviewData()
    @StateObject private var threads = AtlasOrbitPreviewData()
    @StateObject private var environments = AtlasEnvironmentPreviewData()
    @StateObject private var presence = AtlasPresencePreviewData()
    @StateObject private var navigation = AtlasNavigation()
    @StateObject private var updater = AtlasUpdater(startingUpdater: false)
    @StateObject private var authentication = AtlasAuthentication()
    @StateObject private var profile = AtlasProfile()
    @State private var showingRepository = true
    @StateObject private var appearance = AtlasAppearance(request: { action in
        if action["operation"] as? String == "themes" { throw CancellationError() }
        return try await AtlasAppearance.bridge(action)
    })
    @StateObject private var accounts = AtlasAIAccounts { _ in
        Data("""
        {"providers":[{"provider":"claude","credential_configured":false,"login_available":true},
        {"provider":"chatgpt","credential_configured":false,"login_available":true}]}
        """.utf8)
    }
    private let server = URL(string: "https://atlas.example.org")!
    private var updates: Bool { ProcessInfo.processInfo.arguments.contains("--updates") }
    private var settings: Bool { ProcessInfo.processInfo.arguments.contains("--settings") }
    private var compact: Bool { ProcessInfo.processInfo.arguments.contains("--compact") }

    var body: some Scene {
        Window("Atlas · Demo workspace", id: "workspace") {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--coding") {
                    NavigationStack { AtlasCodingSettingsView(request: environments.request) }.frame(width: 660, height: 560)
                } else if ProcessInfo.processInfo.arguments.contains("--repository-picker") {
                    NavigationStack { AtlasCodingSettingsView(request: environments.request) }
                        .frame(width: 660, height: 560)
                        .sheet(isPresented: $showingRepository) {
                            AtlasThreadRepositoryPicker(threadId: "00000000-0000-4000-8000-000000000001", selected: "acme/mobile",
                                                        request: environments.request, changed: {})
                        }
                } else if settings {
                    AtlasDesktopSettings(server: server, accounts: accounts, profileRequest: business.request,
                                         profileModel: profile, notifications: nil,
                                         signOut: {}, workstation: environments.workstation, updater: updater)
                } else if updates {
                    AtlasUpdateSettingsView(updater: updater)
                } else if ProcessInfo.processInfo.arguments.contains("--login") {
                    AtlasLoginView(authentication: authentication).frame(minWidth: 820, minHeight: 580)
                } else {
                    AtlasWorkspaceView(holidayRequest: holidays.request, businessRequest: business.request,
                                       orbitRequest: threads.request, orbitLocalRequest: threads.local,
                                       presence: presence.model, navigation: navigation) {
                        AtlasSettingsView(server: server, accounts: accounts, signOut: {}, profileRequest: business.request,
                                          profileModel: profile)
                    }
                    .frame(minWidth: 820, minHeight: 580)
                }
            }
            .environment(\.atlasServer, server)
            .environment(\.atlasEnvironmentRequest, environments.request)
            .modifier(AtlasThemeScope(appearance: appearance, server: server))
            .task {
                await appearance.configure(server: server)
                appearance.choose(theme: "server-default")
                appearance.choose(mode: ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
                if let value = argument("--destination"), let url = URL(string: value) {
                    navigation.receive(url, server: server)
                }
                AtlasMacOSCapture.schedule()
            }
            .alert("Atlas link", isPresented: Binding(
                get: { navigation.message != nil && !navigation.hasVisibleProtectedWork },
                set: { if !$0 { navigation.message = nil } }
            )) {
                Button("OK") { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
        }
        .defaultSize(width: settings ? 660 : (updates ? 420 : (compact ? 820 : 1180)), height: settings ? 640 : (updates ? 220 : 800))
        .windowResizability(updates || settings ? .contentSize : .contentMinSize)
    }

    private func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
