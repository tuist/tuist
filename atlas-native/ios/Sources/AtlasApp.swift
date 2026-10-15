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
                    ForEach(AtlasCore.sections()) { section in
                        Link(destination: authentication.destination(section.url)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.headline)
                                Text(section.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                Section {
                    Text("Sections currently open in your browser, which may ask you to sign in separately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Sign out", role: .destructive) { authentication.signOut() }
                }
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Atlas")
        }
    }
}
