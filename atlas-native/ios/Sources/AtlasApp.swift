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

    private func sectionLabel(_ section: AtlasSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.headline)
            Text(section.description).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

    private var workspace: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your workspace, on the go")
                        .font(.title2.bold())
                    if let server = authentication.server {
                        Text(server.host() ?? "Atlas")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Workspace") {
                    ForEach(AtlasCore.sections().filter { !$0.url.path.hasPrefix("/settings/") }) { section in
                        if section.screen == "time-off" {
                            NavigationLink {
                                AtlasTimeOffView(title: section.title, request: authentication.holidayRequest)
                            } label: { sectionLabel(section) }
                        } else {
                            Link(destination: authentication.destination(section.url)) { sectionLabel(section) }
                        }
                    }
                }
                Section {
                    Text("Other workspace sections open in your browser, which may ask you to sign in separately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Atlas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        if let server = authentication.server {
                            AtlasSettingsView(
                                server: server,
                                accounts: authentication.accountSettings,
                                signOut: authentication.signOut
                            )
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .tint(AtlasSettingsStyle.tint)
    }
}
