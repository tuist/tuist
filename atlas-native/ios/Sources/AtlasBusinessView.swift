import Charts
import SwiftUI

struct AtlasBusinessView: View {
    @StateObject private var model: AtlasBusiness
    @State private var query = ""
    @State private var creating = false
    @Environment(\.atlasPresence) private var presence

    init(resource: AtlasBusinessResource, request: @escaping ([String: Any]) async throws -> Data) {
        _model = StateObject(wrappedValue: AtlasBusiness(resource: resource, request: request))
    }

    var body: some View {
        List {
            if model.forbidden {
                ContentUnavailableView("Access required", systemImage: "lock", description: Text("Ask an Atlas administrator for access."))
            } else if let page = model.page {
                if model.resource == .invoices {
                    AtlasInvoiceChart(months: page.summary)
                    Section {
                        Text("Manage manual invoices here. Imported invoices are read-only. No payments are made from this screen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(page.items) { original in
                        let item = model.records[original.id] ?? original
                        NavigationLink {
                            AtlasBusinessDetail(model: model, original: item)
                        } label: {
                            AtlasBusinessRow(resource: model.resource, item: item)
                        }
                        .accessibilityIdentifier("business-item-\(item.id)")
                    }
                    if page.items.isEmpty {
                        ContentUnavailableView(
                            model.query.isEmpty ? "No \(model.resource.title.lowercased()) yet" : "No results",
                            systemImage: model.resource.icon,
                            description: Text(model.query.isEmpty ? "Use the add button to create one." : "Try another search.")
                        )
                    }
                } header: {
                    Text(model.query.isEmpty ? "\(page.totalCount) items" : "Results for “\(model.query)” · \(page.totalCount) items")
                }
                if page.totalPages > 1 {
                    Section {
                        HStack {
                            Button("Previous") { Task { await model.load(page: page.page - 1) } }
                                .disabled(page.page <= 1 || model.busy)
                            Spacer()
                            Text("\(page.page) of \(page.totalPages)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Next") { Task { await model.load(page: page.page + 1) } }
                                .disabled(page.page >= page.totalPages || model.busy)
                        }.frame(minHeight: 44)
                    }
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await model.load(query: query, page: model.page?.page ?? 1) } }
                        .disabled(model.busy)
                }
            }
            if model.busy { ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading") }
        }
        .navigationTitle(model.resource.title)
        .searchable(text: $query, prompt: "Search \(model.resource.title.lowercased())")
        .onSubmit(of: .search) { Task { await model.load(query: query) } }
        .onChange(of: query) { _, value in
            if value.isEmpty, !model.query.isEmpty { Task { await model.load(query: "") } }
        }
        .refreshable { await model.load(query: query, page: model.page?.page ?? 1) }
        .task { if model.page == nil { await model.load() } }
        .onAppear { presence?.show(resource: model.resource.rawValue) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.page?.canWrite == true {
                    Button("New \(model.resource.singular)", systemImage: "plus") { creating = true }
                        .disabled(model.busy).accessibilityIdentifier("business-create")
                }
            }
        }
        .sheet(isPresented: $creating) { AtlasBusinessEditor(model: model, editing: nil) }
    }
}

private struct AtlasBusinessRow: View {
    let resource: AtlasBusinessResource
    let item: AtlasBusinessRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                case .accounts:
                    Text([item["segment"].capitalized, item["deal_stage"], item["primary_domain"]]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
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

struct AtlasBusinessDetail: View {
    @ObservedObject var model: AtlasBusiness
    let original: AtlasBusinessRecord
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @Environment(\.atlasPresence) private var presence
    private var item: AtlasBusinessRecord { model.records[original.id] ?? original }

    var body: some View {
        List {
            Section {
                Text(item.title(for: model.resource)).font(.title2.bold()).textSelection(.enabled)
                ForEach(detailFields, id: \.0) { field, label in
                    if !item[field].isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label).font(.caption).foregroundStyle(.secondary)
                            Text(formatted(field)).textSelection(.enabled)
                        }.padding(.vertical, 2)
                    }
                }
            }
            if let message = model.errorMessage { Section { Text(message).foregroundStyle(.red) } }
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
        .navigationTitle(model.resource.singular).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if item.canEdit { Button("Edit") { editing = true }.disabled(model.busy) }
            }
        }
        .sheet(isPresented: $editing) { AtlasBusinessEditor(model: model, editing: item) }
        .confirmationDialog("Delete this \(model.resource.singular.lowercased())?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await model.delete(item) { dismiss() } } }
        } message: { Text("This cannot be undone.") }
        .task { await model.show(original) }
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
            [("description", "Notes"), ("primary_domain", "Domain"), ("segment", "Lifecycle"), ("status", "Status"),
             ("deal_stage", "Deal stage"), ("current_value", "Value"), ("next_renewal_date", "Next renewal"),
             ("legal_name", "Legal name"), ("url", "Website"), ("hosting", "Hosting"), ("plan_tier", "Plan")]
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
        if field == "remind_at", let date = ISO8601DateFormatter().date(from: item[field]) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if field.hasSuffix("_date") || field == "due_on" { return AtlasBusinessFormatting.date(item[field]) }
        return item[field]
    }
}

private struct AtlasInvoiceChart: View {
    let months: [AtlasInvoiceMonth]
    @State private var currency = ""
    private var currencies: [String] { Array(Set(months.map(\.currency))).sorted() }
    private var selected: String { currencies.contains(currency) ? currency : currencies.first ?? "" }
    private var values: [AtlasInvoiceMonth] { months.filter { $0.currency == selected }.sorted { $0.month < $1.month } }

    var body: some View {
        Section {
            if months.isEmpty {
                Text("No dated invoice totals yet.").foregroundStyle(.secondary)
            } else {
                if currencies.count > 1 {
                    Picker("Currency", selection: Binding(get: { selected }, set: { currency = $0 })) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                }
                Chart(values) { month in
                    BarMark(x: .value("Month", month.month), y: .value("Invoice total", Double(month.amount) ?? 0))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(month.month)
                        .accessibilityValue(AtlasBusinessFormatting.money(month.amount, currency: selected))
                }
                .chartYAxisLabel(selected)
                .frame(height: 190)
                DisclosureGroup("Monthly values") {
                    ForEach(values) { month in
                        LabeledContent(month.month, value: AtlasBusinessFormatting.money(month.amount, currency: selected))
                    }
                }
            }
        } header: { Text("Monthly invoice totals") } footer: {
            Text("All invoices, grouped by invoice date. Currencies are shown separately. These are not bank balances or cash flow.")
        }
    }
}
