import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()
    @StateObject private var appearance = AtlasAppearance()
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
            .task(id: authentication.server) { await appearance.configure(server: authentication.server) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await appearance.refresh() } }
            }
            .task { await authentication.restore() }
        }
    }

    @ViewBuilder private var workspace: some View {
        if let server = authentication.server {
            AtlasWorkspaceView(holidayRequest: authentication.holidayRequest,
                               businessRequest: authentication.businessRequest, presence: authentication.presence) {
                AtlasSettingsView(server: server, accounts: authentication.accountSettings, signOut: authentication.signOut,
                                  profileRequest: authentication.businessRequest)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red).padding()
                }
            }
        }
    }
}
