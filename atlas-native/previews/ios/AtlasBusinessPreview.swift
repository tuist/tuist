import Foundation
import SwiftUI

@MainActor
final class AtlasBusinessPreviewData: ObservableObject {
    private var recordAccessRevoked = false
    private var profileDescription = ""
    private var items: [String: [[String: Any]]] = [
        "tasks": [
            AtlasBusinessPreviewData.record(
                "task-1",
                [
                    "title": "Review onboarding",
                    "description": "Prepare materials for the new teammate.",
                    "assignee_name": "Taylor",
                    "assignee_id": "user-1",
                    "status": "open",
                    "due_on": "2026-10-21",
                    "remind_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
                ]
            ),
            AtlasBusinessPreviewData.record(
                "task-2",
                [
                    "title": "Follow up with Northstar",
                    "assignee_name": "Jordan",
                    "assignee_id": "user-2",
                    "account_name": "Northstar",
                    "status": "open",
                    "due_on": "2026-10-23",
                    "remind_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                ]
            ),
            AtlasBusinessPreviewData.record(
                "task-3",
                ["title": "Prepare release notes", "assignee_name": "Taylor", "status": "completed"]
            ),
        ],
        "accounts": [
            AtlasBusinessPreviewData.record(
                "account-1",
                [
                    "name": "Northstar",
                    "primary_domain": "northstar.example.org",
                    "segment": "customer",
                    "status": "active",
                    "currency": "EUR",
                    "current_value": "24500",
                    "contract_value": "24500",
                    "contract_currency": "EUR",
                    "hosting": "cloud",
                ]
            ),
            AtlasBusinessPreviewData.record(
                "account-2",
                ["name": "Fern Studio", "primary_domain": "fern.example.org", "segment": "prospect", "hosting": "unknown"]
            ),
        ],
        "invoices": [
            AtlasBusinessPreviewData.record(
                "invoice-1",
                [
                    "vendor_name": "Cloud hosting",
                    "invoice_number": "INV-1042",
                    "invoice_date": "2026-10-10",
                    "total_amount_value": "1240.50",
                    "total_amount_currency": "EUR",
                    "status": "needs_review",
                ]
            ),
            AtlasBusinessPreviewData.record(
                "invoice-2",
                [
                    "vendor_name": "Design tools",
                    "invoice_number": "INV-1039",
                    "invoice_date": "2026-10-02",
                    "total_amount_value": "180.00",
                    "total_amount_currency": "USD",
                    "status": "extracted",
                ],
                writable: false
            ),
        ],
    ]

    init() {
        if AtlasSocialPreviewData.enabled { items["accounts"] = AtlasSocialPreviewData.accounts }
        if ProcessInfo.processInfo.arguments.contains("--business-pagination") {
            for index in 4...30 {
                items["tasks", default: []].append(Self.record("task-\(index)", [
                    "title": "Customer follow-up \(index)", "status": "open", "assignee_id": "user-1", "assignee_name": "Taylor",
                ]))
            }
            items["accounts", default: []].insert(Self.record("account-tuist", [
                "name": "Tuist", "primary_domain": "tuist.dev", "segment": "customer", "status": "active",
            ]), at: 0)
            for index in 3...30 {
                items["accounts", default: []].append(Self.record("account-\(index)", [
                    "name": "Customer studio \(index)", "segment": index.isMultiple(of: 2) ? "customer" : "prospect",
                    "status": "active", "deal_stage": "discovery",
                ]))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--deep-links") {
            items["tasks", default: []].append(Self.record("123e4567-e89b-12d3-a456-426614174000", [
                "title": "Deep-linked task beyond the first page", "description": "Opened directly by UUID.", "status": "open"
            ]))
        }
    }

    private static func record(_ id: String, _ fields: [String: String], writable: Bool = true) -> [String: Any] {
        var fields = fields
        if ["open", "completed"].contains(fields["status"] ?? "") {
            if fields["status"] == "completed" { fields["reminder_group"] = "completed" } else {
                let reminder = fields["remind_at"].flatMap { ISO8601DateFormatter().date(from: $0) }
                fields["reminder_group"] = reminder.map { $0 <= Date() ? "overdue" : "upcoming" } ?? "none"
            }
        }
        return ["id": id, "fields": fields, "can_edit": writable, "can_delete": writable]
    }

    func request(_ action: [String: Any]) async throws -> Data {
        let resource = action["resource"] as? String ?? "tasks"
        if ProcessInfo.processInfo.arguments.contains("--delayed-business") {
            try await Task.sleep(for: .milliseconds(700))
        }
        if resource == "profile" {
            if action["action"] as? String == "update_profile" {
                if ProcessInfo.processInfo.arguments.contains("--fail-business-save") {
                    throw AtlasAuthenticationError(kind: "server", message: "Preview save failed. Your draft is still here.")
                }
                profileDescription = (action["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return try JSONSerialization.data(withJSONObject: [
                "server_version": "0.7.2",
                "user": ["name": "Taylor Morgan", "email": "taylor@example.org", "description": profileDescription],
            ])
        }
        if resource == "invoices", ProcessInfo.processInfo.arguments.contains("--forbidden-finance") {
            throw AtlasAuthenticationError(kind: "forbidden", message: "Your Atlas role does not allow this action.")
        }
        let command = action["action"] as? String ?? "list"
        if resource == "tasks", ProcessInfo.processInfo.arguments.contains("--revoke-record-access"),
           recordAccessRevoked || (command == "show" && action["id"] as? String == "123e4567-e89b-12d3-a456-426614174000") {
            recordAccessRevoked = true
            throw AtlasAuthenticationError(kind: "forbidden", message: "Your Atlas role does not allow this action.")
        }
        if command == "list" {
            let query = (action["query"] as? String ?? "").lowercased()
            let filters = action["filters"] as? [String: String] ?? [:]
            var rows = (items[resource] ?? []).filter {
                query
                    .isEmpty ||
                    (($0["fields"] as? [String: String])?.values.joined(separator: " ").lowercased().contains(query) == true)
            }.filter { row in
                let fields = row["fields"] as? [String: String] ?? [:]
                return filters.allSatisfy { key, value in
                    key == "group_by" || value.isEmpty || fields[key == "reminder" ? "reminder_group" : key] == value
                }
            }
            if filters["group_by"] == "reminder" {
                let groups = AtlasTaskReminderGroup.allCases.map(\.rawValue)
                rows.sort {
                    let lhs = ($0["fields"] as? [String: String])?["reminder_group"] ?? "none"
                    let rhs = ($1["fields"] as? [String: String])?["reminder_group"] ?? "none"
                    return (groups.firstIndex(of: lhs) ?? 2) < (groups.firstIndex(of: rhs) ?? 2)
                }
            }
            let page = action["page"] as? Int ?? 1
            let total = rows.count
            let start = min((page - 1) * 25, total)
            rows = Array(rows[start..<min(start + 25, total)])
            let summary: [[String: String]] = resource == "invoices" ? [
                ["month": "2026-07", "currency": "EUR", "amount": "950.40"],
                ["month": "2026-08", "currency": "EUR", "amount": "1420.80"],
                ["month": "2026-09", "currency": "EUR", "amount": "1080.00"],
                ["month": "2026-10", "currency": "EUR", "amount": "1240.50"],
                ["month": "2026-10", "currency": "USD", "amount": "180.00"],
            ] : []
            var result: [String: Any] = [
                "items": rows, "page": page, "total_pages": max(1, (total + 24) / 25), "total_count": total, "can_write": true,
                "summary": summary, "options": [
                    "users": [["id": "user-1", "name": "Taylor"], ["id": "user-2", "name": "Jordan"]],
                    "accounts": [["id": "account-1", "name": "Northstar"]],
                    "segments": ["customer", "lead", "prospect"],
                    "statuses": resource == "invoices" ? ["needs_review", "extracted", "failed"] : [
                        "active",
                        "churned",
                        "paused",
                        "trial",
                    ],
                    "deal_stages": ["poc", "discovery"],
                ],
            ]
            if resource == "invoices", page == 1, !ProcessInfo.processInfo.arguments.contains("--legacy-finance") {
                let empty = ProcessInfo.processInfo.arguments.contains("--empty-finance")
                let missingFX = ProcessInfo.processInfo.arguments.contains("--missing-finance-fx")
                result["finance_overview"] = [
                    "currency": "EUR", "as_of": "2026-10-22", "account_count": empty ? 0 : 3,
                    "available_cash": empty || missingFX ? NSNull() : "120000.25",
                    "monthly_burn": empty || missingFX ? NSNull() : "15000",
                    "runway_months": empty || missingFX ? NSNull() : "8",
                    "fx_published_on": "2026-10-21", "excluded_currencies": missingFX ? ["USD"] : [],
                    "months": empty || missingFX ? [] : [
                        ["month": "2026-05", "income": "23000", "expense": "32000"],
                        ["month": "2026-06", "income": "26000", "expense": "40000"],
                        ["month": "2026-07", "income": "21000", "expense": "37000"],
                        ["month": "2026-08", "income": "25000", "expense": "38000"],
                        ["month": "2026-09", "income": "30000", "expense": "42000"],
                        ["month": "2026-10", "income": "18000.50", "expense": "27000.75"]
                    ]
                ]
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
        var rows = items[resource] ?? []
        let id = action["id"] as? String
        let index = rows.firstIndex { $0["id"] as? String == id }
        if command == "show" {
            guard let index else { throw AtlasAuthenticationError(kind: "unavailable", message: "This record could not be found.") }
            var item = rows[index]
            if resource == "accounts", id == "account-1" {
                item["details"] = [
                    "fields": ["overview_summary": "Growing customer evaluating cloud runners.", "handles": "northstar-production"],
                    "address": ["city": "Berlin", "country": "DE"],
                    "billing": ["email": "billing@northstar.example.org", "vat_id": "DE123456789"],
                    "signatory": ["name": "Taylor Morgan", "title": "CTO"],
                    "children": [],
                    "contacts": [Self.record("contact-1", ["full_name": "Jordan Reed", "email": "jordan@northstar.example.org", "is_primary": "true"])],
                    "terms": [Self.record("term-1", ["start_date": "2026-01-01", "payment": "yearly", "total": "24500", "currency": "EUR"])],
                    "invoices": [Self.record("customer-invoice-1", ["number": "NS-2026-1", "due_date": "2026-11-01", "amount_value": "24500", "amount_currency": "EUR", "status": "scheduled"])],
                    "documents": [Self.record("document-1", ["title": "Master service agreement", "status": "ready", "summary": "Annual agreement for cloud services."])],
                    "events": [Self.record("event-1", ["title": "Runner evaluation", "body": "Agreed on success criteria.", "occurred_at": "2026-10-20T12:00:00Z", "author_name": "Taylor"])],
                    "outcomes": [], "service_levels": []
                ]
            }
            return try JSONSerialization.data(withJSONObject: ["item": item])
        }
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
