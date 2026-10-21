import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()
    @StateObject private var navigation = AtlasNavigation()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authentication.server != nil {
                    workspace
                } else {
                    AtlasLoginView(authentication: authentication)
                }
            }
            .tint(AtlasBrand.accent)
            .environment(\.atlasNavigation, navigation)
            .task { await authentication.restore(); navigation.resolve(server: authentication.server) }
            .onOpenURL { navigation.receive($0, server: authentication.server) }
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
                               businessRequest: authentication.businessRequest, presence: authentication.presence, navigation: navigation) {
                AtlasSettingsView(server: server, accounts: authentication.accountSettings, signOut: authentication.signOut,
                                  profileRequest: authentication.businessRequest)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red).padding()
                }
            }
            .tint(AtlasSettingsStyle.tint)
        }
    }
}
