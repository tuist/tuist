import SwiftUI

struct AtlasConnectionsView: View {
    @ObservedObject var model: AtlasConnections
    @State private var disconnecting: AtlasConnection?
    @Environment(\.atlasPresence) private var presence
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Form {
            Section {
                ForEach(model.connections) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: connection.provider == "slack" ? "number" :
                                    connection.provider == "github" ? "chevron.left.forwardslash.chevron.right" : "globe")
                                .foregroundStyle(.tint).frame(width: 32).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connection.name).font(.headline)
                                Text(connection.summary).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        let actions = textSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                            : AnyLayout(HStackLayout())
                        actions {
                            Button(connection.connected ? "Reconnect" : "Connect") {
                                Task { await model.connect(connection.provider) }
                            }
                            .buttonStyle(.borderedProminent)
                            .modifier(AtlasPrimaryAction())
                            .disabled(!connection.configured || model.busy)
                            .accessibilityLabel("\(connection.connected ? "Reconnect" : "Connect") \(connection.name)")
                            .accessibilityIdentifier("connection-\(connection.provider)")
                            if connection.connected {
                                if !textSize.isAccessibilitySize { Spacer() }
                                Button("Disconnect", role: .destructive) { disconnecting = connection }
                                    .buttonStyle(.bordered).tint(.red).disabled(model.busy)
                                    .accessibilityLabel("Disconnect \(connection.name)")
                            }
                        }
                        .frame(minHeight: 44)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Connect your personal GitHub, Slack and Google accounts. " +
                     "Authorization opens securely in your browser and returns to Atlas.")
            }
            if model.busy { Section { ProgressView("Updating connections…") } }
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
        #endif
        .modifier(AtlasThemedContent())
        .onAppear { presence?.show() }
        .task { await model.load() }
        .refreshable { await model.load() }
        .protectsAtlasNavigation(model.busy)
        .confirmationDialog("Disconnect \(disconnecting?.name ?? "account")?", isPresented: Binding(
            get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }
        ), titleVisibility: .visible) {
            if let connection = disconnecting {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect(connection.provider) } }
            }
        } message: { Text("Atlas will no longer have access through this connection.") }
    }
}
