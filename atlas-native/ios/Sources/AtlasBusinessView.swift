import SwiftUI

struct AtlasBusinessView: View {
    @StateObject private var model: AtlasBusiness
    @State private var query = ""
    @State private var creating = false
    @State private var listRevision = 0
    private let loadList: Bool
    @Environment(\.atlasPresence) private var presence

    init(resource: AtlasBusinessResource, loadList: Bool = true, request: @escaping ([String: Any]) async throws -> Data) {
        self.loadList = loadList
        _model = StateObject(wrappedValue: AtlasBusiness(resource: resource, request: request))
    }

    init(model: AtlasBusiness, loadList: Bool) {
        self.loadList = loadList
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        list.onChange(of: model.page?.page) { previous, page in
            if previous != nil, page == 1 { listRevision += 1 }
        }
    }

    private var list: some View {
        List {
            Color.clear.frame(height: 0)
                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                .environment(\.defaultMinListRowHeight, 0).accessibilityHidden(true).id("business-start")
            if model.forbidden {
                ContentUnavailableView("Access required", systemImage: "lock", description: Text("Ask an Atlas administrator for access."))
            } else if let page = model.page {
                if model.resource == .invoices {
                    AtlasFinanceOverviewView(overview: page.financeOverview)
                    Section {
                        Text("Manage manual invoices here. Imported invoices are read-only. No payments are made from this screen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if !model.filters.isEmpty {
                        Text(activeFilters).font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("business-active-filters")
                    }
                    if model.filters["group_by"] != "reminder" { rows(page.items) }
                    if page.items.isEmpty {
                        ContentUnavailableView(
                            model.query.isEmpty && model.filters.isEmpty ? "No \(model.resource.title.lowercased()) yet" : "No results",
                            systemImage: model.resource.icon,
                            description: Text(model.query.isEmpty && model.filters.isEmpty
                                ? "Use the add button to create one." : "Try another search or change your filters.")
                        )
                    }
                } header: {
                    Text(model.query.isEmpty ? "\(page.totalCount) items" : "Results for “\(model.query)” · \(page.totalCount) items")
                }
                if model.filters["group_by"] == "reminder" {
                    ForEach(AtlasTaskReminderGroup.allCases) { group in
                        let items = page.items.filter { (model.records[$0.id] ?? $0)["reminder_group"] == group.rawValue }
                        if !items.isEmpty { Section(group.title) { rows(items) } }
                    }
                }
                if page.page < page.totalPages, !model.nextPageFailed {
                    Section {
                        ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading more")
                            .task(id: page.page) { await model.loadMore() }
                    }
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button(model.nextPageFailed ? "Retry loading more" : "Retry") {
                        Task {
                            if model.nextPageFailed { await model.loadMore(retry: true) } else { await model.load(query: query) }
                        }
                    }
                        .disabled(model.busy)
                }
            }
            if model.busy, !model.loading || model.page == nil {
                ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading")
            }
        }
        // Reset only the list for new criteria; scrolling headers can clip them under native navigation.
        .id(model.query)
        .id(model.filters)
        .id(listRevision)
        .modifier(AtlasThemedContent())
        .navigationTitle(model.resource.title)
        .searchable(text: $query, prompt: "Search \(model.resource.title.lowercased())")
        .onSubmit(of: .search) { Task { await model.load(query: query) } }
        .onChange(of: query) { _, value in
            if value.isEmpty, !model.query.isEmpty { Task { await model.load(query: "") } }
        }
        .refreshable { await model.load(query: query) }
        .task(id: loadList) { if loadList, model.page == nil { await model.load() } }
        .navigationDestination(for: AtlasRecordRoute.self) { route in
            AtlasLinkedBusinessDetail(model: model, id: route.id).id(route.identity)
        }
        .onAppear { presence?.show(resource: model.resource.rawValue) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { AtlasBrowserButton(screen: model.resource.rawValue) }
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu.disabled(model.busy && !model.loading)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if model.page?.canWrite == true {
                    Button("New \(model.resource.singular)", systemImage: "plus") { creating = true }
                        .disabled(model.busy).accessibilityIdentifier("business-create")
                }
            }
        }
        .sheet(isPresented: $creating) { AtlasBusinessEditor(model: model, editing: nil) }
    }

    private func rows(_ items: [AtlasBusinessRecord]) -> some View {
        ForEach(items) { original in
            let item = model.records[original.id] ?? original
            NavigationLink {
                AtlasBusinessDetail(model: model, original: item)
            } label: {
                AtlasBusinessRow(resource: model.resource, item: item)
            }
            .accessibilityIdentifier("business-item-\(item.id)")
        }
    }

    private var filterMenu: some View {
        Menu {
            switch model.resource {
            case .tasks:
                filterPicker("Status", key: "status", values: ["open", "completed"])
                Picker("Assigned to", selection: filterBinding("assignee_id")) {
                    Text("Anyone").tag("")
                    ForEach(model.options.users) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                Picker("Reminder", selection: filterBinding("reminder")) {
                    Text("Any reminder").tag("")
                    Text("Overdue").tag("overdue")
                    Text("Upcoming").tag("upcoming")
                    Text("No reminder").tag("none")
                }.pickerStyle(.menu)
                Picker("Group by", selection: filterBinding("group_by")) {
                    Text("None").tag("")
                    Text("Reminder").tag("reminder")
                }.pickerStyle(.menu)
            case .accounts:
                filterPicker("Lifecycle", key: "segment", values: model.options.segments)
                filterPicker("Status", key: "status", values: model.options.statuses)
                filterPicker("Deal stage", key: "deal_stage", values: model.options.dealStages)
            case .invoices:
                filterPicker("Review status", key: "status", values: model.options.statuses)
            }
            if !model.filters.isEmpty {
                Divider()
                Button("Reset filters") { Task { await model.load(filters: [:]) } }
            }
        } label: {
            Label("Filters", systemImage: model.filters.isEmpty
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(activeFilters.isEmpty ? "All records" : activeFilters)
        .accessibilityIdentifier("business-filters")
    }

    private func filterPicker(_ title: String, key: String, values: [String]) -> some View {
        Picker(title, selection: filterBinding(key)) {
            Text("All").tag("")
            ForEach(values, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
        }.pickerStyle(.menu)
    }

    private func filterBinding(_ key: String) -> Binding<String> {
        Binding(get: { model.filters[key] ?? "" }, set: { value in Task { await model.setFilter(key, value: value) } })
    }

    private var activeFilters: String {
        model.filters.sorted { $0.key < $1.key }.map { key, value in
            if key == "assignee_id" { return model.options.users.first { $0.id == value }?.name ?? "Assigned to someone" }
            if key == "group_by" { return "Grouped by reminder" }
            if key == "reminder" { return value == "none" ? "No reminder" : "\(value.capitalized) reminders" }
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }.joined(separator: " · ")
    }
}

private struct AtlasBusinessRow: View {
    let resource: AtlasBusinessResource
    let item: AtlasBusinessRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if resource == .accounts { AtlasAccountLogo(item: item) }
            if resource == .tasks {
                Image(systemName: item["status"] == "completed" ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item["status"] == "completed" ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(item["status"].capitalized)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title(for: resource)).font(.headline).foregroundStyle(.primary)
                switch resource {
                case .tasks:
                    Text([item["assignee_name"], item["account_name"]].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !item["due_on"].isEmpty {
                        Text("Due \(AtlasBusinessFormatting.date(item["due_on"]))").font(.caption).foregroundStyle(.secondary)
                    }
                    if !item["remind_at"].isEmpty, item["status"] != "completed" {
                        Label("\(item["reminder_group"] == "overdue" ? "Overdue reminder" : "Reminder") · " +
                            AtlasBusinessFormatting.dateTime(item["remind_at"]), systemImage: "bell")
                            .font(.caption).foregroundStyle(item["reminder_group"] == "overdue" ? Color.red : Color.secondary)
                    }
                case .accounts:
                    Text([item["segment"].capitalized, item["deal_stage"].replacingOccurrences(of: "_", with: " ").capitalized,
                          item["primary_domain"]]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !item["contract_value"].isEmpty {
                        Text(AtlasBusinessFormatting.money(item["contract_value"], currency: item["contract_currency"]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .invoices:
                    Text(AtlasBusinessFormatting.money(item["total_amount_value"], currency: item["total_amount_currency"]))
                        .font(.subheadline).monospacedDigit()
                    Text([AtlasBusinessFormatting.date(item["invoice_date"]), item.canEdit ? "Manual" : "Imported"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(minHeight: 44, alignment: .leading).padding(.vertical, 4)
    }
}

struct AtlasAccountLogo: View {
    let item: AtlasBusinessRecord

    private var url: URL? {
        guard !item["primary_domain"].isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [URLQueryItem(name: "domain", value: item["primary_domain"]), URLQueryItem(name: "sz", value: "128")]
        return components.url
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(String(item["name"].prefix(1)).uppercased()).font(.headline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
        }
        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

struct AtlasBusinessDetail: View {
    @ObservedObject var model: AtlasBusiness
    let original: AtlasBusinessRecord
    var reloadOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @Environment(\.atlasPresence) private var presence
    private var item: AtlasBusinessRecord { model.records[original.id] ?? original }

    var body: some View {
        List {
            if model.resource == .accounts {
                AtlasAccountDetailSections(item: item)
            } else {
                Section {
                    Text(item.title(for: model.resource)).font(.title2.bold()).textSelection(.enabled)
                        .accessibilityIdentifier("destination-\(model.resource.rawValue)-\(item.id)")
                    ForEach(detailFields, id: \.0) { field, label in
                        if !item[field].isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                                Text(formatted(field)).textSelection(.enabled)
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }
            if let message = model.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    if model.page == nil {
                        Button("Retry loading options") { Task { await model.load() } }.disabled(model.busy)
                    }
                }
            }
            if model.resource == .tasks, item["status"] == "open", item.canEdit {
                Section {
                    Button("Mark complete", systemImage: "checkmark.circle") { Task { _ = await model.complete(item) } }
                        .disabled(model.busy)
                }
            }
            if model.resource == .invoices, !item.canEdit {
                Section { Text("Imported invoices are read-only. Manage their source in Atlas.").foregroundStyle(.secondary) }
            }
            if item.canDelete {
                Section {
                    Button("Delete \(model.resource.singular.lowercased())", role: .destructive) { deleting = true }.disabled(model.busy)
                }
            }
            if model.busy { ProgressView() }
        }
        .modifier(AtlasThemedContent())
        .navigationTitle(model.resource.singular).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { AtlasBrowserButton(screen: model.resource.rawValue, recordID: item.id) }
            ToolbarItem(placement: .topBarTrailing) {
                if item.canEdit { Button("Edit") { editing = true }.disabled(model.busy || model.page == nil) }
            }
        }
        .protectsAtlasNavigation(model.mutating && !editing)
        .toolbar(model.mutating ? .hidden : .visible, for: .tabBar)
        .sheet(isPresented: $editing, onDismiss: { Task { await model.show(original) } }, content: {
            AtlasBusinessEditor(model: model, editing: item)
        })
        .confirmationDialog("Delete this \(model.resource.singular.lowercased())?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await model.delete(item) { dismiss() } } }
        } message: { Text("This cannot be undone.") }
        .task { if reloadOnAppear { await model.show(original) } }
        .refreshable { await model.show(original) }
        .onAppear { presence?.show(resource: model.resource.rawValue, id: original.id) }
        .onChange(of: model.forbidden) { _, denied in
            if denied { editing = false; dismiss() }
        }
    }

    private var detailFields: [(String, String)] {
        switch model.resource {
        case .tasks:
            [("description", "Notes"), ("status", "Status"), ("assignee_name", "Assigned to"),
             ("account_name", "Account"), ("due_on", "Due date"), ("remind_at", "Reminder")]
        case .accounts:
            []
        case .invoices:
            [("invoice_number", "Invoice number"), ("invoice_date", "Invoice date"), ("due_date", "Due date"),
             ("total_amount_value", "Total"), ("status", "Review status")]
        }
    }

    private func formatted(_ field: String) -> String {
        if field == "current_value" { return AtlasBusinessFormatting.money(item[field], currency: item["currency"]) }
        if field == "total_amount_value" {
            return AtlasBusinessFormatting.money(item[field], currency: item["total_amount_currency"])
        }
        if field == "remind_at" { return AtlasBusinessFormatting.dateTime(item[field]) }
        if field.hasSuffix("_date") || field == "due_on" { return AtlasBusinessFormatting.date(item[field]) }
        return item[field]
    }
}
