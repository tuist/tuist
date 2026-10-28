import SwiftUI

struct AtlasDesktopBusinessTable: View {
    @ObservedObject var model: AtlasBusiness
    let activeFilters: String
    @State private var selection: String?
    @State private var openedRecord: String?
    @State private var sortOrder: [AtlasDesktopRecordSort] = []
    @State private var showingOverview = true

    var body: some View {
        VStack(spacing: 0) {
            if model.forbidden {
                ContentUnavailableView("Access required", systemImage: "lock",
                                       description: Text("Ask an Atlas administrator for access."))
            } else {
                if model.resource == .invoices, let page = model.page {
                    DisclosureGroup("Finance overview", isExpanded: $showingOverview) {
                        Form { AtlasFinanceOverviewView(overview: page.financeOverview) }
                            .formStyle(.grouped).frame(height: 300)
                    }
                    .padding(12)
                    Divider()
                }
                table
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                    .contextMenu(forSelectionType: String.self) { ids in
                        Button("Open \(model.resource.singular)") { openedRecord = ids.first }
                            .disabled(ids.isEmpty)
                    } primaryAction: { ids in openedRecord = ids.first }
                    .onKeyPress(.return) {
                        guard let selection else { return .ignored }
                        openedRecord = selection
                        return .handled
                    }
                    .onKeyPress(keys: ["o"], phases: .down) { key in
                        guard key.modifiers == .command, let selection else { return .ignored }
                        openedRecord = selection
                        return .handled
                    }
                    .overlay {
                        if let page = model.page, page.items.isEmpty, !model.loading {
                            ContentUnavailableView("No results", systemImage: model.resource.icon,
                                                   description: Text("Try another search or change your filters."))
                        }
                    }
                    .accessibilityIdentifier("business-table")
                    .accessibilityHint("Double-click a row or press Command-O to open it.")
            }
            Divider()
            footer
        }
        .navigationDestination(item: $openedRecord) { id in
            AtlasLinkedBusinessDetail(model: model, id: id)
        }
        .onChange(of: model.page?.items.map(\.id)) { _, ids in
            if let selection, ids?.contains(selection) != true { self.selection = nil }
        }
    }

    @ViewBuilder private var table: some View {
        let records = items
        switch model.resource {
        case .accounts:
            Table(records, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Account", sortUsing: AtlasDesktopRecordSort(field: "name")) { item in
                    HStack(spacing: 6) {
                        AtlasAccountLogo(item: item, size: 18)
                        title(item, lastID: records.last?.id)
                    }
                }.width(min: 160, ideal: 220)
                TableColumn("Lifecycle", sortUsing: AtlasDesktopRecordSort(field: "segment")) { value($0, "segment") }
                    .width(min: 80, ideal: 100)
                TableColumn("Deal stage", sortUsing: AtlasDesktopRecordSort(field: "deal_stage")) {
                    value($0, "deal_stage")
                }.width(min: 90, ideal: 110)
                TableColumn("Domain", sortUsing: AtlasDesktopRecordSort(field: "primary_domain")) {
                    Text($0["primary_domain"])
                }.width(min: 100, ideal: 180)
                TableColumn("Contract value", sortUsing: AtlasDesktopRecordSort(field: "contract_value")) {
                    amount($0, field: "contract_value", currency: "contract_currency")
                }.width(min: 100, ideal: 130)
            }
        case .tasks:
            Table(records, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Task", sortUsing: AtlasDesktopRecordSort(field: "title")) {
                    title($0, lastID: records.last?.id)
                }.width(min: 180, ideal: 250)
                TableColumn("Status", sortUsing: AtlasDesktopRecordSort(field: "status")) { value($0, "status") }
                    .width(min: 70, ideal: 90)
                TableColumn("Assigned to", sortUsing: AtlasDesktopRecordSort(field: "assignee_name")) {
                    Text($0["assignee_name"])
                }.width(min: 90, ideal: 120)
                TableColumn("Account", sortUsing: AtlasDesktopRecordSort(field: "account_name")) {
                    Text($0["account_name"])
                }.width(min: 90, ideal: 120)
                TableColumn("Due date", sortUsing: AtlasDesktopRecordSort(field: "due_on")) {
                    Text(AtlasBusinessFormatting.date($0["due_on"]))
                }.width(min: 90, ideal: 110)
                TableColumn("Reminder", sortUsing: AtlasDesktopRecordSort(field: "remind_at")) { item in
                    Text(item["remind_at"].isEmpty ? "" : AtlasBusinessFormatting.dateTime(item["remind_at"]))
                        .foregroundStyle(item["reminder_group"] == "overdue" ? Color.red : Color.primary)
                }.width(min: 110, ideal: 170)
                TableColumn("Reminder group") {
                    Text(AtlasTaskReminderGroup(rawValue: $0["reminder_group"])?.title ?? "")
                }.width(min: 120, ideal: 150)
            }
        case .invoices:
            Table(records, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Vendor", sortUsing: AtlasDesktopRecordSort(field: "vendor_name")) {
                    title($0, lastID: records.last?.id)
                }.width(min: 140, ideal: 200)
                TableColumn("Invoice", sortUsing: AtlasDesktopRecordSort(field: "invoice_number")) {
                    Text($0["invoice_number"])
                }.width(min: 90, ideal: 120)
                TableColumn("Date", sortUsing: AtlasDesktopRecordSort(field: "invoice_date")) {
                    Text(AtlasBusinessFormatting.date($0["invoice_date"]))
                }.width(min: 90, ideal: 110)
                TableColumn("Amount", sortUsing: AtlasDesktopRecordSort(field: "total_amount_value")) {
                    amount($0, field: "total_amount_value", currency: "total_amount_currency")
                }.width(min: 100, ideal: 130)
                TableColumn("Review status", sortUsing: AtlasDesktopRecordSort(field: "status")) { value($0, "status") }
                    .width(min: 100, ideal: 130)
                TableColumn("Editing") { Text($0.canEdit ? "Editable" : "Read-only") }
                    .width(min: 70, ideal: 80)
            }
        }
    }

    private var items: [AtlasBusinessRecord] {
        let records = (model.page?.items ?? []).map { model.records[$0.id] ?? $0 }.sorted(using: sortOrder)
        guard model.filters["group_by"] == "reminder" else { return records }
        let groups = AtlasTaskReminderGroup.allCases.map(\.rawValue)
        return records.sorted {
            (groups.firstIndex(of: $0["reminder_group"]) ?? groups.count)
                < (groups.firstIndex(of: $1["reminder_group"]) ?? groups.count)
        }
    }

    private func title(_ item: AtlasBusinessRecord, lastID: String?) -> some View {
        Text(item.title(for: model.resource)).lineLimit(1)
            .accessibilityIdentifier("business-item-\(item.id)")
            .task(id: model.page?.page) {
                if item.id == lastID, !model.nextPageFailed { await model.loadMore() }
            }
    }

    private func value(_ item: AtlasBusinessRecord, _ field: String) -> some View {
        Text(item[field].replacingOccurrences(of: "_", with: " ").capitalized).lineLimit(1)
    }

    private func amount(_ item: AtlasBusinessRecord, field: String, currency: String) -> some View {
        Text(AtlasBusinessFormatting.money(item[field], currency: item[currency]))
            .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            .help("Sorted numerically within each currency, without currency conversion.")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.errorMessage {
                HStack {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("Retry") {
                        Task {
                            if model.nextPageFailed { await model.loadMore(retry: true) } else { await model.load() }
                        }
                    }.disabled(model.busy)
                }
            }
            HStack {
                if let page = model.page {
                    Text(page.items.count == page.totalCount
                         ? "\(page.totalCount) items" : "\(page.items.count) of \(page.totalCount) items")
                    if !sortOrder.isEmpty, page.page < page.totalPages { Text("· Sorting loaded rows") }
                    if !activeFilters.isEmpty {
                        Text("· \(activeFilters)").accessibilityIdentifier("business-active-filters")
                    }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
            }.font(.caption).foregroundStyle(.secondary)
            if model.resource == .invoices {
                Text("Manual bookkeeping only. Imported invoices are read-only. No payments are made here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

struct AtlasDesktopRecordSort: SortComparator {
    let field: String
    var order: SortOrder = .forward

    func compare(_ lhs: AtlasBusinessRecord, _ rhs: AtlasBusinessRecord) -> ComparisonResult {
        let result: ComparisonResult
        if field == "contract_value" || field == "total_amount_value" {
            let currency = field == "contract_value" ? "contract_currency" : "total_amount_currency"
            let currencies = lhs[currency].localizedStandardCompare(rhs[currency])
            if currencies != .orderedSame {
                result = currencies
            } else if let left = Decimal(string: lhs[field], locale: Locale(identifier: "en_US_POSIX")),
                      let right = Decimal(string: rhs[field], locale: Locale(identifier: "en_US_POSIX")) {
                result = NSDecimalNumber(decimal: left).compare(NSDecimalNumber(decimal: right))
            } else {
                result = lhs[field].localizedStandardCompare(rhs[field])
            }
        } else {
            result = lhs[field].localizedStandardCompare(rhs[field])
        }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
