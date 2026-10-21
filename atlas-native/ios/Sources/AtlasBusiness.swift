import Foundation
import SwiftUI

enum AtlasBusinessResource: String, CaseIterable, Identifiable {
    case tasks, accounts, invoices
    var id: String { rawValue }
    var section: AtlasSection { AtlasCatalog().sections.first { $0.screen == rawValue }! }
    var title: String {
        self == .invoices ? AtlasCatalog().groups.first { $0.id == section.group }!.title : section.title
    }
    var singular: String {
        switch self {
        case .tasks: "Task"
        case .accounts: "Account"
        case .invoices: "Invoice"
        }
    }
    var icon: String {
        switch self {
        case .tasks: "checklist"
        case .accounts: "building.2"
        case .invoices: "chart.bar"
        }
    }
}

struct AtlasBusinessRecord: Decodable, Identifiable {
    let id: String
    var fields: [String: String]
    let canEdit: Bool
    let canDelete: Bool
    subscript(_ field: String) -> String { fields[field] ?? "" }

    func title(for resource: AtlasBusinessResource) -> String {
        self[resource == .tasks ? "title" : resource == .accounts ? "name" : "vendor_name"]
    }
}

struct AtlasBusinessChoice: Decodable, Identifiable {
    let id: String
    let name: String
}

struct AtlasBusinessOptions: Decodable {
    var users: [AtlasBusinessChoice] = []
    var accounts: [AtlasBusinessChoice] = []
    var segments: [String] = []
    var statuses: [String] = []
    var dealStages: [String] = []
}

struct AtlasInvoiceMonth: Decodable, Identifiable {
    let month: String
    let currency: String
    let amount: String
    var id: String { "\(month)-\(currency)" }
}

struct AtlasBusinessPage: Decodable {
    let items: [AtlasBusinessRecord]
    let page: Int
    let totalPages: Int
    let totalCount: Int
    let canWrite: Bool
    let options: AtlasBusinessOptions
    let summary: [AtlasInvoiceMonth]
}

private struct AtlasBusinessMutation: Decodable { let item: AtlasBusinessRecord }

enum AtlasTaskReminderGroup: String, CaseIterable, Identifiable {
    case overdue, upcoming, none, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overdue: "Overdue reminders"
        case .upcoming: "Upcoming reminders"
        case .none: "No reminder"
        case .completed: "Completed"
        }
    }
}

@MainActor
final class AtlasBusiness: ObservableObject {
    let resource: AtlasBusinessResource
    @Published private(set) var page: AtlasBusinessPage?
    @Published private(set) var records: [String: AtlasBusinessRecord] = [:]
    @Published private(set) var busy = false
    @Published private(set) var loading = false
    @Published private(set) var nextPageFailed = false
    @Published private(set) var filters: [String: String] = [:]
    @Published private(set) var options = AtlasBusinessOptions()
    @Published private(set) var forbidden = false
    @Published var errorMessage: String?
    private(set) var query = ""
    private var generation = 0
    private let request: ([String: Any]) async throws -> Data

    init(resource: AtlasBusinessResource, request: @escaping ([String: Any]) async throws -> Data) {
        self.resource = resource
        self.request = request
    }

    func load(query: String? = nil, page: Int = 1, filters: [String: String]? = nil) async {
        guard !busy || loading else { return }
        let query = query ?? self.query
        let filters = (filters ?? self.filters).filter { !$0.value.isEmpty }
        if query != self.query || filters != self.filters {
            self.page = nil
            records = [:]
        }
        self.query = query
        self.filters = filters
        generation += 1
        let identity = generation
        busy = true
        loading = true
        nextPageFailed = false
        errorMessage = nil
        defer { if identity == generation { busy = false; loading = false } }
        do {
            let response = try await requestPage(page)
            guard identity == generation, !Task.isCancelled else { return }
            accept(response)
        } catch is CancellationError {} catch {
            if identity == generation { report(error) }
        }
    }

    func setFilter(_ key: String, value: String) async {
        var filters = self.filters
        filters[key] = value
        await load(filters: filters)
    }

    func loadMore(retry: Bool = false) async {
        guard !busy, let page, page.page < page.totalPages, !nextPageFailed || retry else { return }
        let identity = generation
        busy = true
        loading = true
        nextPageFailed = false
        errorMessage = nil
        defer { if identity == generation { busy = false; loading = false } }
        do {
            let response = try await requestPage(page.page + 1)
            guard identity == generation, !Task.isCancelled else { return }
            var ids = Set(page.items.map(\.id))
            let items = page.items + response.items.filter { ids.insert($0.id).inserted }
            accept(response, items: items)
        } catch is CancellationError {} catch {
            if identity == generation {
                nextPageFailed = true
                report(error)
            }
        }
    }

    func show(_ item: AtlasBusinessRecord) async {
        guard !busy else { return }
        records[item.id] = records[item.id] ?? item
        busy = true
        defer { busy = false }
        do {
            let response: AtlasBusinessMutation = try await call(["action": "show", "id": item.id])
            records[item.id] = response.item
        } catch is CancellationError {} catch { report(error) }
    }

    func save(fields: [String: String], editing: AtlasBusinessRecord?) async -> Bool {
        var action: [String: Any] = ["action": editing == nil ? "create" : "update", "fields": fields]
        if let editing { action["id"] = editing.id }
        return await mutate(action)
    }

    func complete(_ item: AtlasBusinessRecord) async -> Bool {
        await mutate(["action": "complete", "id": item.id])
    }

    func delete(_ item: AtlasBusinessRecord) async -> Bool {
        await mutate(["action": "delete", "id": item.id])
    }

    private func mutate(_ action: [String: Any]) async -> Bool {
        guard !busy else { return false }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            if action["action"] as? String == "delete" {
                var input = action
                input["resource"] = resource.rawValue
                _ = try await request(input)
                if let id = action["id"] as? String {
                    records.removeValue(forKey: id)
                    updatePage(deletedID: id)
                }
            } else {
                let response: AtlasBusinessMutation = try await call(action)
                records[response.item.id] = response.item
                updatePage(item: response.item)
            }
        } catch is CancellationError { return false } catch { report(error); return false }
        do { accept(try await requestPage(1)) } catch {
            report(error)
            errorMessage = "Saved. The list could not refresh. Pull to refresh for current results."
        }
        return true
    }

    private func updatePage(item: AtlasBusinessRecord? = nil, deletedID: String? = nil) {
        guard let page else { return }
        var items = page.items.filter { $0.id != deletedID && $0.id != item?.id }
        if let item { items.insert(item, at: 0) }
        self.page = AtlasBusinessPage(items: items, page: page.page, totalPages: page.totalPages,
                                      totalCount: page.totalCount, canWrite: page.canWrite, options: page.options, summary: page.summary)
    }

    private func requestPage(_ page: Int) async throws -> AtlasBusinessPage {
        try await call(["action": "list", "query": query, "page": page, "filters": filters])
    }

    private func accept(_ response: AtlasBusinessPage, items: [AtlasBusinessRecord]? = nil) {
        page = AtlasBusinessPage(items: items ?? response.items, page: response.page, totalPages: response.totalPages,
                                 totalCount: response.totalCount, canWrite: response.canWrite,
                                 options: response.options, summary: response.summary)
        options = response.options
        forbidden = false
        nextPageFailed = false
        for item in response.items { records[item.id] = item }
    }

    private func call<Value: Decodable>(_ action: [String: Any]) async throws -> Value {
        var input = action
        input["resource"] = resource.rawValue
        let data = try await request(input)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: data)
    }

    private func report(_ error: Error) {
        if (error as? AtlasAuthenticationError)?.kind == "forbidden" {
            forbidden = true
            page = nil
            records = [:]
            options = AtlasBusinessOptions()
            nextPageFailed = false
        }
        errorMessage = error.localizedDescription
    }
}

enum AtlasBusinessFormatting {
    static func money(_ amount: String, currency: String) -> String {
        guard let decimal = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), !currency.isEmpty else {
            return [amount, currency].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    static func date(_ value: String) -> String {
        guard let date = AtlasHolidayDates.decode(value) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
