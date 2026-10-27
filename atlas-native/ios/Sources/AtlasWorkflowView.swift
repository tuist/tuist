import SwiftUI

struct AtlasWorkflowView: View {
    @ObservedObject var authentication: AtlasAuthentication
    let id: String
    @State private var workflow: [String: Any]?
    @State private var values: [String: String] = [:]
    @State private var request: [String: Any]?
    @State private var error: String?
    @State private var reviewing = false
    @State private var busy = false
    @State private var attempted = false
    @State private var execution: String?
    @State private var admitted: String?

    private var fields: [AtlasNativeField] {
        ((workflow?["form"] as? [String: Any])?["fields"] as? [[String: Any]] ?? []).map { AtlasNativeField(value: $0) }
    }
    private var supported: Bool { (workflow?["form"] as? [String: Any])?["supported"] as? Bool ?? false }

    var body: some View {
        Form {
            if let workflow {
                Section {
                    Text(workflow["name"] as? String ?? "Workflow").font(.headline)
                    Text(workflow["description"] as? String ?? "")
                    Text("Version \(workflow["version"] as? Int ?? 0)").foregroundStyle(.secondary)
                }
                if supported {
                    ForEach(fields) { field in
                        Section {
                            AtlasWorkflowField(field: field, value: binding(field)).disabled(request != nil)
                            if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if fields.isEmpty { Text("This workflow requires no input parameters.") }
                    if workflow["can_run"] as? Bool == true {
                        Button(request == nil ? "Review and run" : "Retry this launch") { prepare() }.disabled(busy)
                    } else { Text("You have read-only access to workflows.") }
                } else {
                    Text("This contract needs controls that are not supported on mobile yet. Open Atlas on the web to run it.")
                    if let base = AtlasCore.sections().first(where: { $0.screen == "automation" })?.url {
                        Link("Open workflow on web", destination: authentication.destination(base.appendingPathComponent(id)))
                    }
                }
            } else { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Run workflow")
        .task { await load() }
        .sheet(isPresented: $reviewing, onDismiss: dismissReview) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("You are starting this published version with the following inputs. " +
                             "Approval steps will still require their assigned reviewer.")
                        Text(AtlasNativeForm.pretty(request?["input"] ?? [:]))
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        if let error { Text(error).foregroundStyle(.red) }
                    }.padding()
                }
                .navigationTitle("Review launch")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            reviewing = false
                            if !attempted { request = nil }
                        }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Run") { Task { await run() } }.disabled(busy) }
                }
            }
        }
        .navigationDestination(item: $execution) { id in
            AtlasExecutionView(authentication: authentication, id: id)
        }
    }

    private func dismissReview() {
        if let admitted {
            execution = admitted
            self.admitted = nil
            request = nil
            attempted = false
        } else if !attempted { request = nil }
    }
    private func binding(_ field: AtlasNativeField) -> Binding<String> {
        Binding(get: { values[field.id] ?? field.initial }, set: { values[field.id] = $0 })
    }
    private func load() async {
        do {
            workflow = try await authentication.native(["action": "workflow", "id": id])
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func prepare() {
        do {
            if request == nil {
                request = ["action": "run", "id": id, "revision_id": workflow?["revision_id"] ?? "",
                           "request_id": UUID().uuidString.lowercased(), "input": try AtlasNativeForm.input(fields: fields, values: values)]
            }
            error = nil
            reviewing = true
        } catch { self.error = error.localizedDescription }
    }
    private func run() async {
        guard let request else { return }
        busy = true
        attempted = true
        defer { busy = false }
        do {
            let result = try await authentication.launch(request)
            admitted = result["id"] as? String
            reviewing = false
        } catch {
            self.error = error.localizedDescription
            if let failure = error as? AtlasAuthenticationError,
               ["revision_changed", "invalid_input"].contains(failure.kind) {
                self.request = nil
                attempted = false
                reviewing = false
                if failure.kind == "revision_changed" { await load() }
            }
        }
    }
}

struct AtlasWorkflowField: View {
    let field: AtlasNativeField
    @Binding var value: String
    private var label: String { field.title + (field.required ? " *" : "") }

    var body: some View {
        switch field.kind {
        case "boolean":
            Picker(label, selection: $value) {
                if !field.required { Text("Not provided").tag("") }
                Text("Yes").tag("true")
                Text("No").tag("false")
            }
        case "enum":
            Picker(label, selection: $value) {
                Text(field.required ? "Choose…" : "Not provided").tag("")
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case "date": dateInput
        case "text": TextField(label, text: $value, axis: .vertical).lineLimit(3...8)
        default:
            TextField(label, text: $value)
                .keyboardType(["integer", "number"].contains(field.kind) ? .numbersAndPunctuation : .default)
        }
    }
    @ViewBuilder private var dateInput: some View {
        if !field.required {
            Toggle("Provide \(field.title)", isOn: Binding(get: { !value.isEmpty }, set: {
                value = $0 ? AtlasNativeField.date.string(from: Date()) : ""
            }))
        }
        if field.required || !value.isEmpty {
            DatePicker(label, selection: Binding(get: { AtlasNativeField.date.date(from: value) ?? Date() },
                                                set: { value = AtlasNativeField.date.string(from: $0) }), displayedComponents: .date)
        }
    }
}
