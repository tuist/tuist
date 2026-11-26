import SwiftUI

/// Persisted references and the collection explorer share the same native edge.
/// There is deliberately no NavigationStack here: the shell owns navigation.
struct SessionRecordView: View {
    let client: AppClient
    let thread: String
    let message: String
    let generation: UInt64

    var body: some View {
        NativeResourceView(client: client, generation: generation, entry: .message(thread, message))
            .preference(key: RecordPresentedKey.self, value: true)
    }
}

enum NativeResourceEntry: Hashable {
    case message(String, String)
    case collection(String)
    case record(String, String)
}

private struct ResourceField: Decodable, Identifiable {
    let id: String
    let title: String
    let type: String
    let values: [String]?
    let required: Bool?
    let target: String?
}

private struct ResourceAction: Decodable, Identifiable {
    let id: String
    let title: String
    let operation: String
    let fields: [ResourceField]
}

private struct ResourceRow: Identifiable {
    let id: String
    let revision: UInt64
    let values: [String: String]

    init?(_ value: [String: Any]) {
        guard let id = value["id"] as? String, let revision = value["revision"] as? UInt64 else { return nil }
        self.id = id
        self.revision = revision
        values = value.compactMapValues { $0 as? String }
    }
}

/// Rust owns authority, transport, validation, capability selection and retries.
/// This object only adapts the bridge's plain presentation values to SwiftUI.
@MainActor @Observable private final class NativeResource {
    let client: AppClient
    let generation: UInt64
    let entry: NativeResourceEntry
    private let surfaceID = UUID().uuidString.lowercased()
    var title = ""
    var model = ""
    var fields: [ResourceField] = []
    var filterFields: [ResourceField] = []
    var sortFields: [ResourceField] = []
    var actions: [ResourceAction] = []
    var items: [ResourceRow] = []
    var record: ResourceRow?
    var listQuery: String?
    var connected = false
    var canRetry = false
    var warning: String?
    var error: String?
    var busy = false
    var hasMore = false
    private var active = true
    private var reopening = false

    init(client: AppClient, generation: UInt64, entry: NativeResourceEntry) {
        self.client = client
        self.generation = generation
        self.entry = entry
    }

    private var prefix: String {
        switch entry { case .message: "native_record"; case .collection, .record: "collection" }
    }

    private var context: [String: Any] {
        var args: [String: Any] = ["generation": generation, "surface": surfaceID]
        switch entry {
        case let .message(thread, message): args["thread"] = thread; args["message"] = message
        case let .collection(id): args["collection"] = id
        case let .record(collection, id): args["collection"] = collection; args["record"] = id
        }
        return args
    }

    func call(_ operation: String, _ input: [String: Any] = [:]) async {
        guard !busy, active, client.view.generation == generation else { return }
        busy = true
        defer {
            busy = false
            if reopening { reopening = false; Task { await call("open") } }
        }
        do {
            let result = try await client.call("\(prefix)_\(operation)", context.merging(input) { _, new in new })
            guard active, client.view.generation == generation, !Task.isCancelled else { clear(); return }
            let view = result["surface"] as? [String: Any] ?? [:]
            connected = view["connected"] as? Bool == true
            guard connected else { clear(); error = result["error"] as? String; return }
            title = view["title"] as? String ?? ""
            model = view["model"] as? String ?? ""
            fields = try decode([ResourceField].self, view["fields"] ?? [])
            filterFields = try decode([ResourceField].self, view["filter_fields"] ?? [])
            sortFields = try decode([ResourceField].self, view["sort_fields"] ?? [])
            actions = try decode([ResourceAction].self, view["actions"] ?? [])
            items = (view["items"] as? [[String: Any]] ?? []).compactMap(ResourceRow.init)
            record = (view["record"] as? [String: Any]).flatMap(ResourceRow.init)
            listQuery = view["list_query"] as? String
            canRetry = view["can_retry"] as? Bool == true
            hasMore = view["has_more"] as? Bool == true
            warning = view["warning"] as? String
            error = result["error"] as? String
        } catch {
            clear()
            self.error = error.localizedDescription
        }
    }

    func clear() {
        connected = false
        fields = []; actions = []; items = []; record = nil
        filterFields = []; sortFields = []
        warning = nil; canRetry = false; hasMore = false
        title = ""; model = ""; listQuery = nil
    }

    func setActive(_ value: Bool) {
        active = value
        if !value { clear() }
        else if busy { reopening = true }
        else { Task { await call("open") } }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
}

struct NativeResourceView: View {
    @State private var resource: NativeResource
    @State private var search = ""
    @State private var searching = false
    @State private var filters: [String: String] = [:]
    @State private var sort = ""
    @State private var direction = "asc"
    @Environment(\.scenePhase) private var scenePhase

    init(client: AppClient, generation: UInt64, entry: NativeResourceEntry) {
        _resource = State(initialValue: NativeResource(client: client, generation: generation, entry: entry))
    }

    var body: some View {
        Group {
            if case .collection = resource.entry {
                List {
                    ResourceStatus(resource: resource)
                    ForEach(resource.items) { row in
                        NavigationLink {
                            NativeResourceDetail(resource: resource, recordID: row.id)
                        } label: {
                            Text(verbatim: row.values["_display_title"] ?? row.id)
                        }
                    }
                    ForEach(resource.actions.filter { $0.operation == "create" }) { action in
                        NavigationLink {
                            ResourceForm(resource: resource, action: action, record: nil)
                        } label: { Text(verbatim: action.title) }
                            .disabled(resource.busy || resource.canRetry || resource.warning != nil)
                    }
                    if resource.connected, resource.items.isEmpty { Text("No records") }
                    if resource.hasMore {
                        Button("Load more records") { Task { await resource.call("query", ["input": ["next": true]]) } }
                            .disabled(resource.busy)
                    }
                }
                .refreshable { await refreshList() }
                .searchable(text: $search, isPresented: $searching, prompt: "Search records")
                .onSubmit(of: .search) { Task { await refreshList() } }
                .onDisappear { searching = false }
                .onChange(of: resource.client.view.navigation.tab) { _, tab in
                    if tab != .profile { searching = false }
                }
                .toolbar {
                    ToolbarItem {
                        Menu {
                            ForEach(resource.filterFields.filter { $0.values != nil }) { field in
                                Picker(selection: Binding(get: { filters[field.id] ?? "" }, set: { filters[field.id] = $0 })) {
                                    Text("All records").tag("")
                                    ForEach(field.values ?? [], id: \.self) { Text(verbatim: $0).tag($0) }
                                } label: { Text(verbatim: field.title) }
                            }
                            Picker("Sort records", selection: $sort) {
                                Text("Default order").tag("")
                                ForEach(resource.sortFields) { Text(verbatim: $0.title).tag($0.id) }
                            }
                            Picker("Sort direction", selection: $direction) {
                                Text("Ascending").tag("asc")
                                Text("Descending").tag("desc")
                            }
                        } label: { Label("Filter and sort", systemImage: "line.3.horizontal.decrease") }
                            .disabled(resource.busy || !resource.connected)
                    }
                }
                .onChange(of: filters) { Task { await refreshList() } }
                .onChange(of: sort) { Task { await refreshList() } }
                .onChange(of: direction) { Task { await refreshList() } }
            } else {
                NativeResourceDetail(resource: resource, recordID: nil)
            }
        }
        .navigationTitle(resource.title.isEmpty ? String(localized: "Record") : resource.title)
        .overlay { if resource.busy { ProgressView() } }
        .task { await resource.call("open") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { resource.setActive(false) }
            if phase == .active { resource.setActive(true) }
        }
    }

    private func refreshList() async {
        var input: [String: Any] = ["search": search, "filters": filters.filter { !$0.value.isEmpty }]
        if !sort.isEmpty { input["sort"] = sort; input["direction"] = direction }
        if let query = resource.listQuery { await resource.call("query", ["query": query, "input": input]) }
        else { await resource.call("open") }
    }
}

private struct NativeResourceDetail: View {
    let resource: NativeResource
    let recordID: String?

    private var record: ResourceRow? {
        guard recordID == nil || resource.record?.id == recordID else { return nil }
        return resource.record
    }

    var body: some View {
        Form {
            ResourceStatus(resource: resource)
            if let record {
                ForEach(resource.fields) { field in
                    if let target = field.target, let id = record.values[field.id], field.type == "reference" {
                        NavigationLink {
                            NativeResourceView(
                                client: resource.client,
                                generation: resource.generation,
                                entry: .record(target, id)
                            )
                        } label: {
                            LabeledContent { Text(verbatim: id) } label: { Text(verbatim: field.title) }
                        }
                        .disabled(resource.busy || resource.canRetry)
                    } else {
                        LabeledContent { Text(verbatim: record.values[field.id] ?? "—").textSelection(.enabled) }
                            label: { Text(verbatim: field.title) }
                    }
                }
                ForEach(resource.actions.filter { $0.operation != "create" }) { action in
                    NavigationLink {
                        ResourceForm(resource: resource, action: action, record: record)
                    } label: { Text(verbatim: action.title) }
                        .disabled(resource.busy || resource.canRetry || resource.warning != nil)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(resource.title.isEmpty ? String(localized: "Record") : resource.title)
        .task(id: recordID) {
            if let recordID { await resource.call("refresh", ["model": resource.model, "id": recordID]) }
        }
        .refreshable {
            if let record { await resource.call("refresh", ["model": resource.model, "id": record.id]) }
            else { await resource.call("open") }
        }
    }
}

private struct ResourceStatus: View {
    let resource: NativeResource
    var body: some View {
        if let error = resource.error { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
        if let warning = resource.warning { Text(LocalizedStringKey(warning)).foregroundStyle(.secondary) }
        if resource.canRetry {
            Button("Retry submission") { Task { await resource.call("retry") } }.disabled(resource.busy)
        }
        if !resource.connected, !resource.busy {
            Button("Open again") { Task { await resource.call("open") } }
        }
    }
}

private struct ResourceForm: View {
    let resource: NativeResource
    let action: ResourceAction
    let record: ResourceRow?
    @State private var values: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ResourceStatus(resource: resource)
            if resource.connected, resource.actions.contains(where: { $0.id == action.id }) {
                ForEach(action.fields) { field in
                    let value = Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 })
                    if field.type == "enum" {
                        Picker(selection: value) {
                            Text("Not set").tag("")
                            ForEach(field.values ?? [], id: \.self) { Text(verbatim: $0).tag($0) }
                        } label: { Text(verbatim: field.title) }
                    } else {
                        TextField(text: value) { Text(verbatim: field.title) }
                    }
                }
                Button("Save") {
                    Task {
                        var input: [String: Any] = ["values": values]
                        if let record { input["id"] = record.id; input["expected_revision"] = record.revision }
                        await resource.call(
                            "action",
                            ["action": action.id, "request_id": UUID().uuidString.lowercased(), "input": input]
                        )
                        if resource.connected, resource.error == nil, !resource.canRetry { dismiss() }
                    }
                }
                .disabled(resource.busy || !resource.connected || resource.canRetry || resource.warning != nil)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(resource.connected ? action.title : String(localized: "Record"))
        .onChange(of: resource.connected) { _, connected in
            values = connected ? Dictionary(uniqueKeysWithValues: action.fields.map { ($0.id, "") }) : [:]
        }
        .onChange(of: resource.canRetry) { _, canRetry in
            if !canRetry, resource.connected, resource.error == nil { dismiss() }
        }
        .onAppear {
            if values.isEmpty, resource.connected {
                values = Dictionary(uniqueKeysWithValues: action.fields.map { ($0.id, record?.values[$0.id] ?? "") })
            }
        }
    }
}

struct CollectionsView: View {
    let client: AppClient
    @State private var collections: [Collection] = []
    @State private var error: String?
    @State private var loading = false
    private struct Collection: Decodable, Identifiable { let id: String; let title: String }

    var body: some View {
        List {
            if let error { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
            ForEach(collections) { collection in
                NavigationLink {
                    NativeResourceView(client: client, generation: client.view.generation, entry: .collection(collection.id))
                } label: { Text(verbatim: collection.title) }
            }
            if collections.isEmpty, !loading, error == nil { Text("No collections") }
            if error != nil { Button("Try again") { Task { await load() } } }
        }
        .navigationTitle("Collections")
        .overlay { if loading { ProgressView() } }
        .task(id: client.view.generation) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !loading else { return }
        let generation = client.view.generation
        collections = []; error = nil; loading = true
        defer { loading = false }
        do {
            let response = try await client.call("collections", ["generation": generation])
            guard generation == client.view.generation, !Task.isCancelled else { return }
            collections = try JSONDecoder().decode(
                [Collection].self,
                from: JSONSerialization.data(withJSONObject: response["collections"] ?? [])
            )
        } catch { self.error = error.localizedDescription }
    }
}

struct RecordPresentedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
