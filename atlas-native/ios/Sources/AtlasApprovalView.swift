import SwiftUI

struct AtlasApprovalView: View {
    @ObservedObject var authentication: AtlasAuthentication
    let id: String
    @State private var approval: [String: Any]?
    @State private var error: String?
    @State private var decision: String?
    @State private var execution: String?
    @State private var busy = false
    @State private var loadRevision = UUID()

    var body: some View {
        List {
            if let approval {
                if approval["cached"] as? Bool == true {
                    Section("Saved approval") {
                        Text(approval["step_id"] as? String ?? "Approval")
                        Text("Connect to load the exact request before reviewing a decision.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Exact request") {
                    Text("Review this persisted payload. Your decision applies to precisely this request, not an editable replacement.")
                    Text((approval["payload_json"] as? String ?? "Not recorded"))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if approval["status"] as? String == "pending" && approval["can_decide"] as? Bool == true {
                    Button("Approve") { decision = "approved" }.disabled(busy)
                    Button("Reject", role: .destructive) { decision = "rejected" }.disabled(busy)
                } else if approval["cached"] as? Bool != true { Text("This request has already been resolved.") }
            } else { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Review approval")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Confirm your decision for the displayed request", isPresented: Binding(
            get: { decision != nil }, set: { if !$0 { decision = nil } }
        ), titleVisibility: .visible) {
            if let selected = decision {
                Button(selected == "approved" ? "Approve this request" : "Reject this request") {
                    decision = nil
                    Task { await decide(selected) }
                }
            }
        }
        .navigationDestination(item: $execution) { id in
            AtlasExecutionView(authentication: authentication, id: id)
        }
    }
    private func load() async {
        let revision = UUID()
        loadRevision = revision
        if approval == nil, let data = await authentication.cachedRead(["operation": "native", "action": "approval", "id": id]),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           loadRevision == revision, !Task.isCancelled { approval = saved }
        do {
            let fresh = try await authentication.native(["action": "approval", "id": id])
            try Task.checkCancellation()
            guard loadRevision == revision else { return }
            approval = fresh
            error = nil
        } catch is CancellationError { } catch {
            guard loadRevision == revision, !Task.isCancelled else { return }
            if AtlasReadCache.accessDenied(error) { approval = nil; decision = nil }
            self.error = error.localizedDescription
        }
    }
    private func decide(_ value: String) async {
        guard approval?["cached"] as? Bool != true else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await authentication.native(["action": "decide", "id": id, "decision": value,
                                                           "payload_digest": approval?["payload_digest"] ?? ""])
            execution = result["id"] as? String
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
