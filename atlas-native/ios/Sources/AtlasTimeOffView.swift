import SwiftUI

struct AtlasTimeOffView: View {
    let title: String
    @StateObject private var model: AtlasTimeOff
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.atlasReadCache) private var cachedRead
    private struct Editor: Identifiable {
        let id = UUID()
        let request: AtlasHolidayRequest?
    }
    @State private var editor: Editor?
    @State private var cancelling: AtlasHolidayRequest?

    init(title: String, request: @escaping ([String: Any]) async throws -> Data) {
        self.title = title
        _model = StateObject(wrappedValue: AtlasTimeOff(request: request))
    }

    var body: some View {
        List {
            Section {
                Button { editor = Editor(request: nil) } label: {
                    Label("Request holiday", systemImage: "calendar.badge.plus")
                        .frame(minHeight: 44)
                }
                .disabled(model.overview?.cached == true)
                Text("Dates are inclusive. Working-day counts exclude weekends and Berlin public holidays.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Refresh") { Task { await model.load() } }
                }
            }
            if let overview = model.overview {
                Section("My requests") {
                    if overview.requests.items.isEmpty { Text("No holiday requests yet.").foregroundStyle(.secondary) }
                    ForEach(overview.requests.items) { booking in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(booking.startsOn) – \(booking.endsOn)").font(.headline)
                            Text(booking.status.capitalized).foregroundStyle(booking.status == "rejected" ? Color.red : Color.secondary)
                            if let days = booking.workingDays { Text("\(days) working days").font(.subheadline) }
                            if !booking.missingYears.isEmpty {
                                Text("Public holiday calendar incomplete").font(.footnote).foregroundStyle(.orange)
                            }
                            HStack {
                                if booking.canEdit {
                                    Button("Edit request") { editor = Editor(request: booking) }
                                }
                                if booking.canCancel {
                                    Button("Cancel holiday", role: .destructive) { cancelling = booking }
                                }
                            }.buttonStyle(.bordered).controlSize(.large).disabled(overview.cached == true)
                        }.padding(.vertical, 6)
                    }
                    pagination(page: overview.requests, requests: true)
                }
                Section("Berlin public holidays") {
                    ForEach(overview.publicHolidays.items) { holiday in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(holiday.name)
                            Text(holiday.date).foregroundStyle(.secondary)
                        }
                    }
                    if overview.publicHolidays.items.isEmpty {
                        Text("Public holidays will appear after the automatic calendar sync completes.")
                    }
                    pagination(page: overview.publicHolidays, requests: false)
                }
            } else if model.busy { ProgressView("Loading holidays…") }
        }
        .modifier(AtlasThemedContent())
        .navigationTitle(title)
        .toolbar {
            AtlasPresenceToolbar()
            ToolbarItem(placement: .primaryAction) { AtlasBrowserButton(screen: "time-off") }
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }.keyboardShortcut("r")
            }
            #endif
        }
        .disabled(model.busy)
        .protectsAtlasNavigation(model.mutating && editor == nil)
        #if os(iOS)
        .toolbar(model.mutating ? .hidden : .visible, for: .tabBar)
        #endif
        .refreshable { await model.load() }
        .task {
            model.cachedRequest = AtlasReadCache.scoped(cachedRead, operation: "time_off")
            await model.load()
        }
        .sheet(item: $editor) {
            AtlasHolidayForm(model: model, editing: $0.request).dynamicTypeSize(dynamicTypeSize)
        }
        .confirmationDialog("Cancel this holiday?", isPresented: Binding(
            get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }
        ), titleVisibility: .visible) {
            if let booking = cancelling {
                Button("Cancel holiday", role: .destructive) { Task { await model.cancel(booking) }; cancelling = nil }
            }
        }
    }

    @ViewBuilder private func pagination<Item>(page: AtlasHolidayPage<Item>, requests: Bool) -> some View {
        if page.totalPages > 1 {
            HStack {
                Button { load(page.page - 1, requests: requests) } label: {
                    Text("Previous").frame(minWidth: 44, minHeight: 44)
                }.disabled(page.page <= 1)
                Spacer()
                Text("\(page.page) / \(page.totalPages)").foregroundStyle(.secondary)
                Spacer()
                Button { load(page.page + 1, requests: requests) } label: {
                    Text("Next").frame(minWidth: 44, minHeight: 44)
                }.disabled(page.page >= page.totalPages)
            }.buttonStyle(.borderless).frame(minHeight: 44)
        }
    }

    private func load(_ page: Int, requests: Bool) {
        Task {
            await model.load(requestsPage: requests ? page : model.overview?.requests.page ?? 1,
                             holidaysPage: requests ? model.overview?.publicHolidays.page ?? 1 : page)
        }
    }
}

private struct AtlasHolidayForm: View {
    @ObservedObject var model: AtlasTimeOff
    let editing: AtlasHolidayRequest?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var first: Date
    @State private var last: Date

    init(model: AtlasTimeOff, editing: AtlasHolidayRequest?) {
        self.model = model
        self.editing = editing
        _first = State(initialValue: editing.flatMap { AtlasHolidayDates.decode($0.startsOn) } ?? .now)
        _last = State(initialValue: editing.flatMap { AtlasHolidayDates.decode($0.endsOn) } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    dateField("First day away", selection: $first, range: AtlasHolidayDates.bounds, identifier: "holiday-start-date")
                    dateField("Last day away", selection: $last,
                              range: first...AtlasHolidayDates.bounds.upperBound, identifier: "holiday-end-date")
                } footer: {
                    Text("Both dates are inclusive. Changing an approved request's dates requires approval again.")
                }
                if let message = model.errorMessage { Text(message).foregroundStyle(.red) }
                Button(editing == nil ? "Request holiday" : "Save changes") {
                    Task {
                        if await model.save(
                            startsOn: AtlasHolidayDates.encode(first), endsOn: AtlasHolidayDates.encode(last), editing: editing
                        ) {
                            dismiss()
                        }
                    }
                }.frame(minHeight: 44).disabled(model.busy)
                if model.busy { ProgressView("Saving holiday…") }
            }
            .modifier(AtlasThemedContent())
            .environment(\.calendar, AtlasHolidayDates.calendar)
            .navigationTitle(editing == nil ? "Request holiday" : "Edit request")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(width: 540, height: 480)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.busy)
                }
            }
            .interactiveDismissDisabled(model.busy)
            .onChange(of: first) { _, value in if last < value { last = value } }
            .onAppear { model.errorMessage = nil }
        }
        .protectsAtlasNavigation()
    }

    @ViewBuilder private func dateField(
        _ title: String, selection: Binding<Date>, range: ClosedRange<Date>, identifier: String
    ) -> some View {
        let picker = DatePicker(title, selection: selection, in: range, displayedComponents: .date)
            .accessibilityIdentifier(identifier)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                picker.labelsHidden()
            }
        } else { picker }
    }
}
