import SwiftUI

struct AtlasAccountDetailSections: View {
    let item: AtlasBusinessRecord

    var body: some View {
        Section {
            HStack(spacing: 12) {
                AtlasAccountLogo(item: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item["name"]).font(.title2.bold())
                    Text(item["primary_domain"]).font(.subheadline).foregroundStyle(.secondary)
                }
            }.textSelection(.enabled)
        }
        Section("Overview") {
            values(
                overviewFields,
                fields: [
                    ("segment", "Lifecycle"), ("status", "Status"), ("deal_stage", "Deal stage"),
                    ("contract_value", "Contract value"), ("next_renewal_date", "Next renewal"),
                    ("poc_end_date", "POC ends"), ("hosting", "Hosting"), ("plan_tier", "Plan"),
                    ("legal_name", "Legal name"), ("url", "Website")
                ], currency: item["contract_currency"].isEmpty ? item["currency"] : item["contract_currency"])
            if let details = item.details {
                values(
                    details.fields,
                    fields: [
                        ("parent_account_name", "Parent account"), ("handles", "Handles"),
                        ("contract_id", "Contract ID"), ("stripe_customer_id", "Stripe customer"),
                        ("churned_date", "Churned"), ("churn_reason", "Churn reason"), ("latest_activity_at", "Latest activity")
                    ])
                if let summary = details.fields["overview_summary"], !summary.isEmpty {
                    DisclosureGroup("Summary") { Text(summary).textSelection(.enabled) }
                }
            }
            if !item["description"].isEmpty {
                DisclosureGroup("Notes") { Text(item["description"]).textSelection(.enabled) }
            }
        }
        if let details = item.details {
            related(
                "Contacts", records: details.contacts, title: "full_name",
                fields: [
                    ("title", "Role"), ("email", "Email"), ("linkedin_url", "LinkedIn"),
                    ("is_primary", "Primary contact"), ("is_decision_maker", "Decision maker"), ("notes", "Notes")
                ])
            related(
                "Contract terms", records: details.terms, title: "start_date",
                fields: [
                    ("start_date", "Starts"), ("end_date", "Ends"), ("payment", "Payment"), ("seats", "Seats"),
                    ("price_per_seat", "Price per seat"), ("discount", "Discount"), ("total", "Total"),
                    ("on_premise", "On premise"), ("renewal_notice_weeks", "Renewal notice (weeks)"), ("po_number", "PO number")
                ], currencyField: "currency")
            Section("Billing and address") {
                values(details.address, fields: [("street", "Street"), ("city", "City"), ("zip", "Postal code"), ("country", "Country")])
                values(
                    details.billing,
                    fields: [
                        ("tax_id", "Tax ID"), ("vat_id", "VAT ID"), ("sold_to", "Sold to"),
                        ("bill_to", "Bill to"), ("email", "Billing email"), ("phone", "Billing phone")
                    ])
                values(details.signatory, fields: [("name", "Signatory"), ("title", "Signatory title")])
                if [details.address, details.billing, details.signatory].allSatisfy({ $0.values.allSatisfy(\.isEmpty) }) {
                    Text("No billing or address details yet.").foregroundStyle(.secondary)
                }
            }
            related(
                "Customer invoices", records: details.invoices, title: "number",
                fields: [
                    ("due_date", "Due"), ("amount_value", "Amount"), ("status", "Status")
                ], currencyField: "amount_currency")
            related(
                "Outcomes", records: details.outcomes, title: "title",
                fields: [
                    ("status", "Status"), ("health", "Health"), ("motion", "Motion"), ("owner_name", "Owner"),
                    ("target_date", "Target date"), ("description", "Description"), ("success_measure", "Success measure"),
                    ("baseline", "Baseline"), ("target", "Target")
                ])
            related(
                "Documents", records: details.documents, title: "title",
                fields: [
                    ("document_date", "Date"), ("status", "Status"), ("summary", "Summary")
                ])
            related(
                "Service levels", records: details.serviceLevels, title: "name",
                fields: [
                    ("category", "Category"), ("target", "Target"), ("measurement_window", "Measurement window"),
                    ("applies_from", "From"), ("applies_until", "Until"), ("service_credit", "Service credit"),
                    ("exclusions", "Exclusions")
                ])
            related("Child accounts", records: details.children, title: "name", fields: [("primary_domain", "Domain")])
            related(
                "Activity", records: details.events, title: "title",
                fields: [
                    ("occurred_at", "Date"), ("author_name", "Author"), ("kind", "Type"), ("body", "Details")
                ])
        }
    }

    private var overviewFields: [String: String] {
        var fields = item.fields
        if fields["contract_value"] == nil { fields["contract_value"] = fields["current_value"] }
        return fields
    }

    private func related(
        _ label: String, records: [AtlasAccountRelatedRecord], title: String,
        fields: [(String, String)], currencyField: String = "currency"
    ) -> some View {
        Section {
            DisclosureGroup("\(label) (\(records.count))") {
                if records.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                ForEach(records) { record in
                    NavigationLink {
                        List {
                            Section {
                                Text(record[title].isEmpty ? label : formatted(record[title], field: title))
                                    .font(.headline).textSelection(.enabled)
                                values(record.fields, fields: fields, currency: record[currencyField])
                            }
                        }
                        .modifier(AtlasThemedContent())
                        .navigationTitle(label).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Text(record[title].isEmpty ? label : formatted(record[title], field: title))
                    }
                }
            }.accessibilityIdentifier("account-related-\(title)-\(label)")
        }
    }

    private func values(_ data: [String: String], fields: [(String, String)], currency: String = "") -> some View {
        ForEach(fields, id: \.0) { key, label in
            if let value = data[key], !value.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(formatted(value, field: key, currency: currency)).textSelection(.enabled)
                }.padding(.vertical, 2)
            }
        }
    }

    private func formatted(_ value: String, field: String, currency: String = "") -> String {
        if ["contract_value", "price_per_seat", "discount", "total", "amount_value"].contains(field) {
            return AtlasBusinessFormatting.money(value, currency: currency)
        }
        if field.hasSuffix("_at") { return AtlasBusinessFormatting.dateTime(value) }
        if field.hasSuffix("_date") || ["applies_from", "applies_until"].contains(field) { return AtlasBusinessFormatting.date(value) }
        if ["is_primary", "is_decision_maker", "on_premise"].contains(field) { return value == "true" ? "Yes" : "No" }
        if ["segment", "status", "deal_stage", "hosting", "plan_tier", "payment", "health", "motion", "category", "kind"].contains(field) {
            return value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        }
        return value
    }
}
