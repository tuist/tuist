import SwiftUI

struct AtlasAutomationView: View {
    @ObservedObject var authentication: AtlasAuthentication
    @Environment(\.scenePhase) private var phase
    @State private var destination = "workflows"
    @State private var items: [AtlasNativeItem] = []
    @State private var error: String?
    @State private var page = 1
    @State private var pages = 1
    @State private var loading = false
    @State private var pending: [String: Any]?
    @State private var resumed: String?
    @State private var loadedScope: String?
    @State private var loadRevision = UUID()

    var body: some View {
        List {
            Picker("Automation", selection: $destination) {
                Text("Workflows").tag("workflows")
                Text("Activity").tag("executions")
                Text("Approvals").tag("approvals")
            }.pickerStyle(.segmented)
            if pending != nil {
                Section("Unconfirmed launch") {
                    Text("Atlas may have accepted your last request. Retry it safely before starting another.")
                    Button("Retry pending launch") { Task { await resume() } }.disabled(loading)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if items.isEmpty && !loading {
                ContentUnavailableView("Nothing here yet", systemImage: "bolt.horizontal.circle",
                                       description: Text("Pull to refresh or choose another section."))
            }
            ForEach(items) { item in
                NavigationLink {
                    detail(item)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(destination == "approvals" ? "Review \(item.text("step_id"))" : item.text("name"))
                        Text(destination == "workflows" ? item.text("description") :
                                item.text("status").replacingOccurrences(of: "_", with: " "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if pages > 1 {
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page <= 1 || loading)
                    Spacer()
                    Text("\(page) of \(pages)").font(.caption)
                    Spacer()
                    Button("Next") { page += 1 }.disabled(page >= pages || loading)
                }
            }
        }
        .overlay { if loading && items.isEmpty { ProgressView("Loading Automation") } }
        .navigationTitle("Automation")
        .refreshable { await load() }
        .task(id: "\(destination):\(page):\(phase)") {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .onChange(of: destination) { _, _ in page = 1 }
        .navigationDestination(item: $resumed) { id in
            AtlasExecutionView(authentication: authentication, id: id)
        }
    }

    @ViewBuilder private func detail(_ item: AtlasNativeItem) -> some View {
        switch destination {
        case "workflows": AtlasWorkflowView(authentication: authentication, id: item.id)
        case "approvals": AtlasApprovalView(authentication: authentication, id: item.id)
        default: AtlasExecutionView(authentication: authentication, id: item.id)
        }
    }

    private func load() async {
        let scope = "\(destination):\(page)"
        let revision = UUID()
        loadRevision = revision
        loading = true
        defer { if loadRevision == revision { loading = false } }
        let action: [String: Any] = ["operation": "native", "action": destination, "page": page]
        if loadedScope != scope {
            items = []
            loadedScope = scope
            if let data = await authentication.cachedRead(action),
               let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               loadRevision == revision, scope == "\(destination):\(page)", !Task.isCancelled {
                accept(saved)
            }
        }
        do {
            let response = try await authentication.native(["action": destination, "page": page])
            guard loadRevision == revision, scope == "\(destination):\(page)", !Task.isCancelled else { return }
            accept(response)
            pending = try authentication.pendingLaunch()
            error = nil
        } catch is CancellationError { } catch {
            guard loadRevision == revision, scope == "\(destination):\(page)", !Task.isCancelled else { return }
            if AtlasReadCache.accessDenied(error) { items = [] }
            self.error = error.localizedDescription
        }
    }

    private func accept(_ response: [String: Any]) {
        items = (response["items"] as? [[String: Any]] ?? []).map { AtlasNativeItem(value: $0) }
        pages = (response["page"] as? [String: Any])?["total"] as? Int ?? 1
    }

    private func resume() async {
        guard let pending else { return }
        loading = true
        defer { loading = false }
        do {
            let response = try await authentication.launch(pending)
            self.pending = nil
            resumed = response["id"] as? String
        } catch { self.error = error.localizedDescription }
    }
}
