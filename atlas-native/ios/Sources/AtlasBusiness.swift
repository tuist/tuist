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

@MainActor
final class AtlasBusiness: ObservableObject {
    let resource: AtlasBusinessResource
    @Published private(set) var page: AtlasBusinessPage?
    @Published private(set) var records: [String: AtlasBusinessRecord] = [:]
    @Published private(set) var busy = false
    @Published private(set) var forbidden = false
    @Published var errorMessage: String?
    private(set) var query = ""
    private let request: ([String: Any]) async throws -> Data

    init(resource: AtlasBusinessResource, request: @escaping ([String: Any]) async throws -> Data) {
        self.resource = resource
        self.request = request
    }

    func load(query: String? = nil, page: Int = 1) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do { try await fetch(query: query ?? self.query, page: page) } catch is CancellationError {} catch { report(error) }
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
        do { try await fetch(query: query, page: page?.page ?? 1) } catch {
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

    private func fetch(query: String, page: Int) async throws {
        let response: AtlasBusinessPage = try await call(["action": "list", "query": query, "page": page])
        self.page = response
        self.query = query
        forbidden = false
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
}
