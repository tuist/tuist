import SwiftUI

struct AtlasApprovalView: View {
    @ObservedObject var authentication: AtlasAuthentication
    let id: String
    @State private var approval: [String: Any]?
    @State private var error: String?
    @State private var decision: String?
    @State private var execution: String?
    @State private var busy = false

    var body: some View {
        List {
            if let approval {
                Section("Exact request") {
                    Text("Review this persisted payload. Your decision applies to precisely this request, not an editable replacement.")
                    Text((approval["payload_json"] as? String ?? "Not recorded"))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                if approval["status"] as? String == "pending" && approval["can_decide"] as? Bool == true {
                    Button("Approve") { decision = "approved" }.disabled(busy)
                    Button("Reject", role: .destructive) { decision = "rejected" }.disabled(busy)
                } else { Text("This request has already been resolved.") }
            } else { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Review approval")
        .task { await load() }
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
        do {
            approval = try await authentication.native(["action": "approval", "id": id])
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func decide(_ value: String) async {
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
