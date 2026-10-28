import SwiftUI

struct AtlasExecutionView: View {
    @ObservedObject var authentication: AtlasAuthentication
    @Environment(\.scenePhase) private var phase
    let id: String
    @State private var record: AtlasNativeItem?
    @State private var error: String?
    @State private var refresh = 0
    @State private var busy = false
    @State private var result: String?
    private let terminal = ["succeeded", "failed", "rejected", "cancelled"]

    var body: some View {
        List {
            if let record {
                Section {
                    Text(record.text("name")).font(.headline)
                    Label(status(record.text("status")), systemImage: symbol(record.text("status")))
                    Text("Completed steps: \(record.value["cursor"] as? Int ?? 0) of \((record.value["steps"] as? [Any])?.count ?? 0)")
                        .foregroundStyle(.secondary)
                    if let milliseconds = record.value["elapsed_ms"] as? NSNumber {
                        Text("Elapsed: \(milliseconds.int64Value / 1000)s").font(.caption)
                    }
                }
                Section("Steps") {
                    ForEach((record.value["steps"] as? [[String: Any]] ?? []).indices, id: \.self) { index in
                        if let steps = record.value["steps"] as? [[String: Any]] {
                            let step = steps[index]
                            Label {
                                VStack(alignment: .leading) {
                                    Text(step["step_id"] as? String ?? "Step")
                                    Text(status(step["status"] as? String ?? "pending")).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: symbol(step["status"] as? String ?? "pending")) }
                        }
                    }
                }
                if let server = authentication.server, !record.text("web_path").isEmpty {
                    Link("Open execution on web", destination: server.appending(path: record.text("web_path")))
                }
                if terminal.contains(record.text("status")) {
                    Section("Results") {
                        if let result { Text(result).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                        Button("Load protected results") { Task { await loadResult() } }
                    }
                }
                if record.value["can_control"] as? Bool == true {
                    if record.text("status") == "failed" {
                        Button("Retry from committed progress") { Task { await control("retry") } }.disabled(busy)
                    } else if !terminal.contains(record.text("status")) {
                        Button("Cancel execution", role: .destructive) { Task { await control("cancel") } }.disabled(busy)
                    }
                }
                if record.text("status") == "waiting_approval" {
                    Text("No processing is happening while this execution awaits its assigned reviewer.")
                }
            } else { ProgressView("Loading execution") }
            if let error {
                Section("Connection") {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reconnect") { refresh += 1 }
                }
            }
        }
        .navigationTitle("Execution")
        .task(id: "\(phase):\(refresh)") { if phase == .active { await follow() } }
    }

    private func follow() async {
        var reconcile = true
        while !Task.isCancelled {
            do {
                let request: [String: Any] = reconcile || record == nil ? ["action": "execution", "id": id] :
                    ["action": "watch", "id": id, "after_sequence": record?.sequence ?? 0]
                let next = AtlasNativeItem(value: try await authentication.native(request))
                if next.sequence >= (record?.sequence ?? 0) { record = next }
                reconcile = false
                error = nil
                if terminal.contains(next.text("status")) { return }
            } catch is CancellationError { return } catch {
                self.error = error.localizedDescription
                reconcile = true
                if let failure = error as? AtlasAuthenticationError, ["forbidden", "unauthorized", "not_found"].contains(failure.kind) {
                    record = nil
                    result = nil
                    return
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private func loadResult() async {
        do {
            let response = try await authentication.native(["action": "result", "id": id])
            let prefix = response["partial"] as? Bool == true ? "Partial outputs\n\n" : ""
            result = prefix + (response["outputs_json"] as? String ?? "Not recorded")
        } catch { self.error = error.localizedDescription }
    }
    private func control(_ command: String) async {
        busy = true
        defer { busy = false }
        do {
            record = AtlasNativeItem(value: try await authentication.native(["action": "control", "id": id, "command": command]))
            refresh += 1
        } catch { self.error = error.localizedDescription }
    }
    private func status(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
    private func symbol(_ value: String) -> String {
        switch value {
        case "succeeded", "approved": "checkmark.circle"
        case "failed", "rejected": "exclamationmark.circle"
        case "waiting_approval": "hourglass"
        case "running": "gearshape"
        case "cancelled": "xmark.circle"
        default: "circle"
        }
    }
}
