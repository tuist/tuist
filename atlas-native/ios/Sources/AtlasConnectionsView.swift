import SwiftUI

struct AtlasConnectionsView: View {
    @ObservedObject var model: AtlasConnections
    @Environment(\.atlasPresence) private var presence

    var body: some View {
        Form {
            Section {
                ForEach(model.connections) { connection in
                    NavigationLink {
                        AtlasConnectionDetailView(provider: connection.provider, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name)
                            Text(connection.summary).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("connection-\(connection.provider)")
                }
            } footer: {
                Text("Your personal account connections are separate from Atlas sign-in and shared workspace integrations.")
            }
            if let message = model.message {
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { Task { await model.load() } }.disabled(model.busy)
                }
            }
        }
        .defaultScrollAnchor(.top)
        .navigationTitle("Connections")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .overlay { if model.busy && model.connections.isEmpty { ProgressView("Loading connections…") } }
        .modifier(AtlasThemedContent())
        .onAppear { presence?.show() }
        .task { await model.load() }
        .refreshable { await model.load() }
        .protectsAtlasNavigation(model.busy)
    }
}

private struct AtlasConnectionDetailView: View {
    let provider: String
    @ObservedObject var model: AtlasConnections
    @State private var confirmingDisconnect = false

    private var connection: AtlasConnection? { model.connections.first { $0.provider == provider } }

    var body: some View {
        Form {
            if let connection {
                Section {
                    LabeledContent("Status", value: connection.status == "connected" ? "Connected" : connection.summary)
                    if let account = connection.accountName {
                        LabeledContent("Account", value: account).textSelection(.enabled)
                    }
                }
                Section {
                    if connection.configured {
                        Button(connection.connected ? "Reconnect \(connection.name)" : "Connect \(connection.name)") {
                            Task { await model.connect(provider) }
                        }
                        .disabled(model.busy || model.cached)
                    } else {
                        Text("\(connection.name) connections aren’t available on this Atlas server.")
                    }
                } footer: {
                    if connection.configured {
                        Text("You’ll authorize access in your browser, then return to Atlas.")
                    } else {
                        Text("An administrator needs to configure \(connection.name) authorization before you can connect.")
                    }
                }
                if connection.connected {
                    Section {
                        Button("Disconnect \(connection.name)", role: .destructive) { confirmingDisconnect = true }
                            .disabled(model.busy || model.cached)
                    }
                }
            }
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(connection?.name ?? "Connection")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar { if model.busy { ProgressView().accessibilityLabel("Updating connection") } }
        .modifier(AtlasThemedContent())
        .refreshable { await model.load() }
        .protectsAtlasNavigation(model.busy)
        .confirmationDialog("Disconnect \(connection?.name ?? "account")?", isPresented: $confirmingDisconnect,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect(provider) }
            }
        } message: { Text("Atlas will no longer have access through this connection.") }
    }
}
