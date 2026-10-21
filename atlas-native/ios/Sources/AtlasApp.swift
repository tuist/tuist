import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()

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
            .task { await authentication.restore() }
        }
    }

    @ViewBuilder private var workspace: some View {
        if let server = authentication.server {
            AtlasWorkspaceView(holidayRequest: authentication.holidayRequest, businessRequest: authentication.businessRequest) {
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
