import Foundation
import SwiftUI

@MainActor
final class AtlasBusinessPreviewData: ObservableObject {
    private var items: [String: [[String: Any]]] = [
        "tasks": [
            Self.record("task-1", ["title": "Review onboarding", "description": "Prepare materials for the new teammate.",
                              "assignee_name": "Taylor", "status": "open", "due_on": "2026-10-21"]),
            Self.record("task-2", ["title": "Follow up with Northstar", "assignee_name": "Jordan", "account_name": "Northstar",
                              "status": "open", "due_on": "2026-10-23"]),
            Self.record("task-3", ["title": "Prepare release notes", "assignee_name": "Taylor", "status": "completed"])
        ],
        "accounts": [
            Self.record("account-1", ["name": "Northstar", "primary_domain": "northstar.example.org", "segment": "customer",
                                 "status": "active", "currency": "EUR", "current_value": "24500", "hosting": "cloud"]),
            Self.record("account-2", ["name": "Fern Studio", "primary_domain": "fern.example.org", "segment": "prospect", "hosting": "unknown"])
        ],
        "invoices": [
            Self.record("invoice-1", ["vendor_name": "Cloud hosting", "invoice_number": "INV-1042", "invoice_date": "2026-10-10",
                                 "total_amount_value": "1240.50", "total_amount_currency": "EUR", "status": "needs_review"]),
            Self.record("invoice-2", ["vendor_name": "Design tools", "invoice_number": "INV-1039", "invoice_date": "2026-10-02",
                                 "total_amount_value": "180.00", "total_amount_currency": "USD", "status": "extracted"], writable: false)
        ]
    ]

    private static func record(_ id: String, _ fields: [String: String], writable: Bool = true) -> [String: Any] {
        ["id": id, "fields": fields, "can_edit": writable, "can_delete": writable]
    }

    func request(_ action: [String: Any]) async throws -> Data {
        let resource = action["resource"] as? String ?? "tasks"
        if resource == "profile" {
            return try JSONSerialization.data(withJSONObject: ["server_version": "0.7.2",
                "user": ["name": "Taylor Morgan", "email": "taylor@example.org"]])
        }
        if resource == "invoices", ProcessInfo.processInfo.arguments.contains("--forbidden-finance") {
            throw AtlasAuthenticationError(kind: "forbidden", message: "Your Atlas role does not allow this action.")
        }
        let command = action["action"] as? String ?? "list"
        if command == "list" {
            let query = (action["query"] as? String ?? "").lowercased()
            let rows = (items[resource] ?? []).filter {
                query.isEmpty || (($0["fields"] as? [String: String])?.values.joined(separator: " ").lowercased().contains(query) == true)
            }
            let summary: [[String: String]] = resource == "invoices" ? [
                ["month": "2026-07", "currency": "EUR", "amount": "950.40"],
                ["month": "2026-08", "currency": "EUR", "amount": "1420.80"],
                ["month": "2026-09", "currency": "EUR", "amount": "1080.00"],
                ["month": "2026-10", "currency": "EUR", "amount": "1240.50"],
                ["month": "2026-10", "currency": "USD", "amount": "180.00"]
            ] : []
            return try JSONSerialization.data(withJSONObject: [
                "items": rows, "page": 1, "total_pages": 1, "total_count": rows.count, "can_write": true,
                "summary": summary, "options": [
                    "users": [["id": "user-1", "name": "Taylor"], ["id": "user-2", "name": "Jordan"]],
                    "accounts": [["id": "account-1", "name": "Northstar"]],
                    "segments": ["customer", "lead", "prospect"],
                    "statuses": resource == "invoices" ? ["needs_review", "extracted", "failed"] : ["active", "churned", "paused", "trial"],
                    "deal_stages": ["poc", "discovery"]
                ]
            ])
        }
        var rows = items[resource] ?? []
        let id = action["id"] as? String
        let index = rows.firstIndex { $0["id"] as? String == id }
        if command == "show", let index { return try JSONSerialization.data(withJSONObject: ["item": rows[index]]) }
        if ProcessInfo.processInfo.arguments.contains("--fail-business-save") {
            throw AtlasAuthenticationError(kind: "server", message: "Preview save failed. Your changes are still here.")
        }
        if command == "delete", let index {
            rows.remove(at: index)
            items[resource] = rows
            return Data("{\"deleted\":true}".utf8)
        }
        var fields = action["fields"] as? [String: String] ?? [:]
        if let index {
            fields = (rows[index]["fields"] as? [String: String] ?? [:]).merging(fields) { _, new in new }
        }
        if command == "complete" { fields["status"] = "completed" }
        if resource == "tasks" { fields["status"] = fields["status"] ?? "open"; fields["assignee_name"] = "Taylor" }
        let item = Self.record(id ?? UUID().uuidString, fields)
        if let index { rows[index] = item } else { rows.insert(item, at: 0) }
        items[resource] = rows
        return try JSONSerialization.data(withJSONObject: ["item": item])
    }
}
