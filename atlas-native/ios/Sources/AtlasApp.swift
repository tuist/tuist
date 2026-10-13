import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()
    @State private var showingSelfHosted = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Text("Your workspace, on the go")
                            .font(.title2.bold())
                        if let server = authentication.server {
                            Text(server.host() ?? "Atlas")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sign in with your Atlas account to access your workspace.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if authentication.server != nil {
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
                    } else {
                        Section {
                            Button("Sign in to Atlas") {
                                Task { await authentication.signIn() }
                            }
                            Button("Self-hosted server") { showingSelfHosted = true }
                            Button("Restore saved session") {
                                Task { await authentication.restore() }
                            }
                        }
                        .disabled(authentication.busy)
                    }
                    if authentication.busy { ProgressView("Signing in…") }
                    if let message = authentication.errorMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }
                .navigationTitle("Atlas")
                .tint(Color(red: 0.44, green: 0.21, blue: 1))
                .task { await authentication.restore() }
                .alert("Self-hosted server", isPresented: $showingSelfHosted) {
                    TextField("https://atlas.example.com", text: $authentication.selfHostedAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Sign in") { Task { await authentication.signIn(selfHosted: true) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Enter the HTTPS address of your Atlas server.")
                }
            }
        }
    }
}
