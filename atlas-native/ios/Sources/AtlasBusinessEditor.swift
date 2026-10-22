import SwiftUI

struct AtlasBusinessEditor: View {
    @ObservedObject var model: AtlasBusiness
    let editing: AtlasBusinessRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [String: String]
    @State private var dirty = false
    @State private var discarding = false
    @State private var saving = false

    init(model: AtlasBusiness, editing: AtlasBusinessRecord?) {
        self.model = model
        self.editing = editing
        var defaults: [String: String] = [:]
        if model.resource == .accounts { defaults = ["segment": "prospect", "hosting": "unknown"] }
        if model.resource == .invoices {
            defaults = ["total_amount_currency": "EUR", "status": "needs_review",
                        "invoice_date": AtlasHolidayDates.encode(Date())]
        }
        _fields = State(initialValue: editing?.fields ?? defaults)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.resource {
                case .tasks: taskFields
                case .accounts: accountFields
                case .invoices: invoiceFields
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                if saving { Section { ProgressView("Saving…") } }
            }
            .disabled(saving)
            .navigationTitle("\(editing == nil ? "New" : "Edit") \(model.resource.singular.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { discarding = true } else { dismiss() } }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if await model.save(fields: payload, editing: editing) { dismiss() }
                            saving = false
                        }
                    }.disabled(!valid || saving || model.busy).accessibilityIdentifier("business-save")
                }
            }
            .interactiveDismissDisabled(dirty || saving)
            .confirmationDialog("Discard changes?", isPresented: $discarding, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
    }

    private var taskFields: some View {
        Group {
            Section("Task") {
                text("Title", "title")
                TextField("Notes", text: binding("description"), axis: .vertical).lineLimit(3...8)
                Picker("Assigned to", selection: binding("assignee_id")) {
                    Text("Me").tag("")
                    ForEach(model.page?.options.users ?? []) { Text($0.name).tag($0.id) }
                }
                Picker("Account", selection: binding("account_id")) {
                    Text("None").tag("")
                    ForEach(model.page?.options.accounts ?? []) { Text($0.name).tag($0.id) }
                }
            }
            Section("Schedule") {
                optionalDate("Due date", "due_on")
                Toggle("Reminder", isOn: Binding(
                    get: { !(fields["remind_at"] ?? "").isEmpty },
                    set: { enabled in
                        fields["remind_at"] = enabled ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)) : ""
                        dirty = true
                    }
                ))
                if !(fields["remind_at"] ?? "").isEmpty {
                    DatePicker("Remind me", selection: Binding(
                        get: { ISO8601DateFormatter().date(from: fields["remind_at"] ?? "") ?? Date() },
                        set: { fields["remind_at"] = ISO8601DateFormatter().string(from: $0); dirty = true }
                    ))
                }
            }
        }
    }

    private var accountFields: some View {
        Group {
            Section("Company") {
                text("Name", "name")
                text("Domain", "primary_domain", keyboard: .URL)
                text("Legal name", "legal_name")
                text("Website", "url", keyboard: .URL)
                TextField("Notes", text: binding("description"), axis: .vertical).lineLimit(3...8)
            }
            Section("Sales") {
                choice("Lifecycle", "segment", values: model.page?.options.segments ?? [], optional: false)
                choice("Status", "status", values: model.page?.options.statuses ?? [])
                choice("Deal stage", "deal_stage", values: model.page?.options.dealStages ?? [])
                text("Value", "current_value", keyboard: .decimalPad)
                text("Currency (ISO code)", "currency", keyboard: .asciiCapable)
                optionalDate("Next renewal", "next_renewal_date")
            }
            Section("Product") {
                choice("Hosting", "hosting", values: ["unknown", "cloud", "self_hosted"], optional: false)
                choice("Plan", "plan_tier", values: ["enterprise", "pro", "free"])
            }
        }
    }

    private var invoiceFields: some View {
        Group {
            Section("Invoice") {
                text("Vendor", "vendor_name")
                text("Invoice number", "invoice_number")
                DatePicker("Invoice date", selection: Binding(
                    get: { AtlasHolidayDates.decode(fields["invoice_date"] ?? "") ?? Date() },
                    set: { fields["invoice_date"] = AtlasHolidayDates.encode($0); dirty = true }
                ), in: AtlasHolidayDates.bounds, displayedComponents: .date)
                optionalDate("Due date", "due_date")
            }
            Section("Total") {
                text("Amount", "total_amount_value", keyboard: .numbersAndPunctuation)
                text("Currency (ISO code)", "total_amount_currency", keyboard: .asciiCapable)
                choice("Review status", "status", values: model.page?.options.statuses ?? [], optional: false)
            }
            Section {
                Text("This records a manual invoice. It does not create a payment or change a bank transaction.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0; dirty = true })
    }

    private func text(_ label: String, _ key: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: binding(key)).keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                .autocorrectionDisabled(keyboard != .default)
                .accessibilityIdentifier("business-field-\(key)")
        }
    }

    private func choice(_ label: String, _ key: String, values: [String], optional: Bool = true) -> some View {
        Picker(label, selection: binding(key)) {
            if optional { Text("None").tag("") }
            ForEach(values, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) }
        }
    }

    private func optionalDate(_ label: String, _ key: String) -> some View {
        Group {
            Toggle(label, isOn: Binding(
                get: { !(fields[key] ?? "").isEmpty },
                set: { fields[key] = $0 ? AtlasHolidayDates.encode(Date()) : ""; dirty = true }
            ))
            if !(fields[key] ?? "").isEmpty {
                DatePicker(label, selection: Binding(
                    get: { AtlasHolidayDates.decode(fields[key] ?? "") ?? Date() },
                    set: { fields[key] = AtlasHolidayDates.encode($0); dirty = true }
                ), in: AtlasHolidayDates.bounds, displayedComponents: .date)
            }
        }
    }

    private var valid: Bool {
        let key = model.resource == .tasks ? "title" : model.resource == .accounts ? "name" : "vendor_name"
        guard !(fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if model.resource == .tasks { return true }
        let amountKey = model.resource == .accounts ? "current_value" : "total_amount_value"
        let value = fields[amountKey] ?? ""
        if model.resource == .invoices {
            let currency = fields["total_amount_currency"] ?? ""
            guard !value.isEmpty, currency.range(of: "^[A-Za-z]{3}$", options: .regularExpression) != nil,
                  AtlasHolidayDates.decode(fields["invoice_date"] ?? "") != nil else { return false }
        }
        return value.isEmpty || normalizedAmount(value).range(of: "^-?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil
    }

    private func normalizedAmount(_ value: String) -> String {
        let separator = Locale.current.decimalSeparator ?? "."
        return value.replacingOccurrences(of: separator, with: ".")
    }

    private var payload: [String: String] {
        let keys: [String]
        switch model.resource {
        case .tasks: keys = ["title", "description", "assignee_id", "account_id", "due_on", "remind_at"]
        case .accounts:
            keys = ["name", "description", "primary_domain", "legal_name", "url", "segment", "status", "deal_stage",
                    "current_value", "currency", "next_renewal_date", "hosting", "plan_tier"]
        case .invoices:
            keys = ["vendor_name", "invoice_number", "invoice_date", "due_date", "total_amount_value", "total_amount_currency", "status"]
        }
        return Dictionary(uniqueKeysWithValues: keys.map { key in
            let value = fields[key] ?? ""
            if key == "current_value" || key == "total_amount_value" { return (key, normalizedAmount(value)) }
            if key == "currency" || key == "total_amount_currency" { return (key, value.uppercased()) }
            return (key, value)
        })
    }
}
