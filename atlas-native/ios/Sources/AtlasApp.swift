import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()
    @StateObject private var navigation = AtlasNavigation()
    @StateObject private var appearance = AtlasAppearance()
    @UIApplicationDelegateAdaptor(AtlasPushDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authentication.server != nil {
                    workspace
                } else {
                    AtlasLoginView(authentication: authentication)
                }
            }
            .modifier(AtlasThemeScope(appearance: appearance, server: authentication.server))
            .task(id: authentication.server) {
                await appearance.configure(server: authentication.server)
                await authentication.pushNotifications.configure(
                    server: authentication.server,
                    request: authentication.server == nil ? nil : authentication.pushRequest
                )
                await authentication.pushNotifications.refresh(token: pushDelegate.token)
            }
            .onChange(of: pushDelegate.token) { _, token in
                Task { await authentication.pushNotifications.refresh(token: token) }
            }
            .onChange(of: pushDelegate.registrationFailed) { _, failed in
                if failed { authentication.pushNotifications.registrationFailed() }
            }
            .onChange(of: pushDelegate.destination, initial: true) { _, url in
                if let url { navigation.receive(url, server: authentication.server); pushDelegate.destination = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await appearance.refresh(); await authentication.pushNotifications.refresh() }
                }
            }
            .environment(\.atlasNavigation, navigation)
            .task { await authentication.restore(); navigation.resolve(server: authentication.server) }
            .onOpenURL { navigation.receive($0, server: authentication.server) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { navigation.receive(url, server: authentication.server) }
            }
            .onChange(of: authentication.server) { previous, server in
                if previous != nil, server == nil { navigation.reset() }
                navigation.resolve(server: server)
            }
            .alert("Atlas link", isPresented: Binding(
                get: { navigation.message != nil && !navigation.hasVisibleProtectedWork },
                set: { if !$0 { navigation.message = nil } }
            )) {
                Button("OK") { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
        }
    }

    @ViewBuilder private var workspace: some View {
        if let server = authentication.server {
            AtlasWorkspaceView(holidayRequest: authentication.holidayRequest,
                               businessRequest: authentication.businessRequest, presence: authentication.presence, navigation: navigation,
                               automation: authentication) {
                AtlasSettingsView(server: server, accounts: authentication.accountSettings, signOut: authentication.signOut,
                                  profileRequest: authentication.businessRequest, notifications: authentication.pushNotifications)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red).padding()
                }
            }
            .environment(\.atlasServer, server)
        }
    }
}
