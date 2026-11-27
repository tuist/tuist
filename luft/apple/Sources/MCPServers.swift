import SwiftUI

/// An MCP server, as `mcp_servers` returns it.
struct MCPServer: Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let connected: Bool

    init(_ json: [String: Any]) {
        id = json["id"] as? String ?? ""
        name = json["name"] as? String ?? ""
        url = json["url"] as? String ?? ""
        connected = json["connected"] as? Bool ?? false
    }
}

/// MCP servers whose tools threads can use: the person's own when
/// `accountHandle` is nil, otherwise the organization's, which only its
/// admins change (the core reports when someone else tries).
struct MCPServersSection: View {
    let client: AppClient
    let accountHandle: String?
    @Binding var sheet: SettingsSheet?
    @State private var servers: [MCPServer]?
    @State private var unavailable = false
    @State private var busy: String?

    var body: some View {
        Section {
            if let servers {
                ForEach(servers) { row($0) }
                Button("Add Server") {
                    sheet = SettingsSheet {
                        AddMCPServerSheet(client: client, accountHandle: accountHandle) { server in
                            Task {
                                await reload()
                                await authorize(server)
                            }
                        }
                    }
                }
            } else if unavailable {
                Text("MCP servers are not available for this account.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            if let accountHandle {
                Text("MCP Servers for \(accountHandle)")
            } else {
                Text("Your MCP Servers")
            }
        } footer: {
            if accountHandle == nil {
                Text("Threads you write in can use the tools of your servers.")
            } else {
                Text("Every thread in this organization can use the tools of its servers. Only admins can change them.")
            }
        }
        .task(id: accountHandle) { await reload() }
    }

    private var arguments: [String: Any] {
        accountHandle.map { ["account_handle": $0] } ?? [:]
    }

    private func row(_ server: MCPServer) -> some View {
        LabeledContent {
            if busy == server.id {
                ProgressView()
            } else {
                HStack {
                    Button(server.connected ? "Sign In Again" : "Sign In") { Task { await authorize(server) } }
                    Button("Remove", role: .destructive) { Task { await remove(server) } }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: server.name)
                Text(verbatim: server.url).font(.footnote).foregroundStyle(.secondary)
                Text(server.connected ? "Connected" : "Not connected")
                    .font(.footnote)
                    .foregroundStyle(server.connected ? .green : .secondary)
            }
        }
    }

    private func reload() async {
        do {
            let data = try await client.call("mcp_servers", arguments)
            servers = (data["servers"] as? [[String: Any]] ?? []).map(MCPServer.init)
            unavailable = false
        } catch {
            if servers == nil { unavailable = true }
        }
    }

    private func authorize(_ server: MCPServer) async {
        busy = server.id
        defer { busy = nil }
        do {
            try await client.authorizeMCPServer(server.id, accountHandle: accountHandle)
            await reload()
        } catch {
            client.error = error.localizedDescription
        }
    }

    private func remove(_ server: MCPServer) async {
        busy = server.id
        defer { busy = nil }
        do {
            _ = try await client.call("remove_mcp_server", arguments.merging(["id": server.id]) { $1 })
            await reload()
        } catch {
            client.error = error.localizedDescription
        }
    }
}

/// Adds a server by its HTTPS URL, then signs in to it.
private struct AddMCPServerSheet: View {
    let client: AppClient
    let accountHandle: String?
    let added: (MCPServer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/mcp", text: $url)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    TextField("Name (optional)", text: $name)
                } footer: {
                    Text("Luft signs in to the server in your browser and keeps the session on the server.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add MCP Server")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Add") { Task { await save() } }
                            .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #endif
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var arguments: [String: Any] = ["url": url, "name": name]
        if let accountHandle { arguments["account_handle"] = accountHandle }
        do {
            let data = try await client.call("add_mcp_server", arguments)
            dismiss()
            if let server = data["server"] as? [String: Any] { added(MCPServer(server)) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
