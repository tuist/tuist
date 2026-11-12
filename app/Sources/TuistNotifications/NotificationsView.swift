import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistServer
import UIKit

/// Profile › Notifications. Notifications are opt-in per device, and what they're about is a list of rules, composed
/// like the Shortcuts app's automations: an event, the conditions that narrow it down, and how to be notified.
public struct NotificationsView: View {
    @EnvironmentObject private var errorHandling: ErrorHandling
    @Environment(\.openURL) private var openURL
    @State private var viewModel: NotificationsViewModel
    @State private var composing: ServerNotificationRule?

    public init() {
        self.init(viewModel: NotificationsViewModel())
    }

    init(viewModel: NotificationsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
            if viewModel.isSupported {
                optInSection
                if viewModel.pushNotifications.permission == .denied {
                    deniedSection
                }
                if viewModel.isOptedIn {
                    rulesSections
                    devicesSection
                }
            } else {
                Section {} footer: {
                    Text("This server doesn't support notifications yet.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(Noora.Colors.accent)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isOptedIn, viewModel.didLoad {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Rule", systemImage: "plus") { composing = ServerNotificationRule() }
                }
            }
        }
        .sheet(item: $composing) { rule in
            NavigationStack {
                RuleEditor(viewModel: viewModel, rule: rule, isNew: true)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: viewModel.pushNotifications.installationID) {
            // This device appears in the list once its registration finishes, after turning notifications on.
            Task { try? await viewModel.reloadDevices() }
        }
    }

    private func load() async {
        do {
            try await viewModel.load()
        } catch is CancellationError {
        } catch {
            // The screen was left mid-load; that's not an error to show.
            guard !Task.isCancelled else { return }
            errorHandling.handle(error: error)
        }
    }

    private var optInSection: some View {
        Section {
            Toggle(
                "Notifications on This Device",
                isOn: asyncBinding(errorHandling) { viewModel.isOptedIn } set: { isOn in
                    try await viewModel.setEnabledOnThisDevice(isOn)
                }
            )
            .disabled(viewModel.pushNotifications.permission == .unknown || viewModel.pendingOptIn != nil)
        } footer: {
            Text("Get notified on this device when your rules match.")
        }
    }

    private var deniedSection: some View {
        Section {
            Button("Turn On in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        } footer: {
            Text("Notifications are turned off for Tuist in iOS Settings.")
        }
    }

    @ViewBuilder
    private var rulesSections: some View {
        if viewModel.isLoading {
            Section("Rules") {
                ProgressView().frame(maxWidth: .infinity)
            }
        } else if viewModel.didLoad {
            if viewModel.rules.isEmpty {
                Section {
                    Button {
                        composing = ServerNotificationRule()
                    } label: {
                        Label("New Rule", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Add a rule to choose which previews notify you, such as a project's beta track.")
                }
            } else {
                Section {
                    ForEach(viewModel.rules) { rule in
                        NavigationLink {
                            RuleEditor(viewModel: viewModel, rule: rule, isNew: false)
                        } label: {
                            RuleCard(rule: rule)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                errorHandling.fireAndHandleError { try await viewModel.delete(rule) }
                            }
                        }
                        .disabled(viewModel.rulesInFlight.contains(rule.id))
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("You're notified once when any of your rules match.")
                }
            }
        }
    }

    private var devicesSection: some View {
        Section {
            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.sortedDevices) { device in
                    deviceRow(device)
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            Text("Devices signed in to Tuist that get notifications. Swipe to remove one.")
        }
    }

    private func deviceRow(_ device: ServerPushDevice) -> some View {
        let isThisDevice = viewModel.isThisDevice(device)
        let platform = device.platform == "android" ? "Android" : "iOS"
        return HStack(spacing: Noora.Spacing.spacing5) {
            Image(systemName: device.platform == "android" ? "smartphone" : "iphone")
                .font(.title3)
                .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Noora.Spacing.spacing1) {
                Text(device.name ?? "\(platform) device")
                    .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                Text(
                    isThisDevice
                        ? "This device"
                        : "\(platform) · Last seen \(device.lastSeenAt.formatted(.relative(presentation: .named)))"
                )
                .font(.footnote)
                .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
            }
        }
        .swipeActions {
            if !isThisDevice {
                Button("Remove", role: .destructive) {
                    errorHandling.fireAndHandleError { try await viewModel.removeDevice(device) }
                }
            }
        }
    }
}

// MARK: - Rule card

private struct RuleCard: View {
    let rule: ServerNotificationRule

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title2)
                .foregroundStyle(rule.isEnabled ? Noora.Colors.accent : Noora.Colors.surfaceLabelTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .font(.headline)
                    .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                Text(rule.isEnabled ? "Send Notification" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

extension ServerNotificationRule {
    var projectsText: String {
        switch projects.count {
        case 0: "Any Project"
        case 1: projects[0]
        default: "\(projects.count) Projects"
        }
    }

    /// The rule as a sentence, the way Shortcuts names an automation.
    var title: String {
        var title = "When a Preview of \(projectsText) Is Published"
        if let track { title += " on \(track.phrase(noun: "Track"))" }
        if let gitBranch { title += " from \(gitBranch.phrase(noun: "Branch"))" }
        if publishedByMe { title += " by Me" }
        return title
    }
}

extension ServerNotificationRule.ValueMatch {
    var label: String {
        switch self {
        case let .is(value): value
        case let .contains(value): "Contains ‘\(value)’"
        }
    }

    func phrase(noun: String) -> String {
        switch self {
        case let .is(value): "‘\(value)’"
        case let .contains(value): "a \(noun) Containing ‘\(value)’"
        }
    }
}

// MARK: - Editor

/// A text condition the user can set from known values or with "Contains…".
private enum Condition: String, Identifiable {
    case track
    case gitBranch = "git_branch"

    var id: String { rawValue }
    var name: String { self == .track ? "Track" : "Branch" }
}

private struct RuleEditor: View {
    @EnvironmentObject private var errorHandling: ErrorHandling
    @Environment(\.dismiss) private var dismiss
    let viewModel: NotificationsViewModel
    @State var rule: ServerNotificationRule
    let isNew: Bool
    @State private var isSaving = false
    @State private var editing: Condition?
    @State private var text = ""
    @State private var trackOptions: [String] = []
    @State private var branchOptions: [String] = []

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProjectsPicker(projects: viewModel.projects, selection: $rule.projects)
                } label: {
                    LabeledContent("Projects") {
                        Text(rule.projectsText).foregroundStyle(Noora.Colors.accent)
                    }
                }
            } header: {
                Text("When a Preview Is Published")
            }
            Section {
                conditionRow(.track, value: $rule.track, options: trackOptions)
                conditionRow(.gitBranch, value: $rule.gitBranch, options: branchOptions)
                Picker("Published By", selection: $rule.publishedByMe) {
                    Text("Anyone").tag(false)
                    Text("Me").tag(true)
                }
                .pickerStyle(.menu)
            } header: {
                Text("Only If")
            } footer: {
                Text(rule.projects.isEmpty
                    ? "Choose projects to pick from the tracks and branches they use."
                    : "Tracks and branches come from the last 90 days of previews.")
            }
            Section("Do") {
                Label("Send Notification", systemImage: "bell.badge.fill")
                    .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
            }
            if !isNew {
                Section {
                    Toggle("Enabled", isOn: $rule.isEnabled)
                }
                Section {
                    Button("Delete Rule", role: .destructive) {
                        errorHandling.fireAndHandleError {
                            try await viewModel.delete(rule)
                            dismiss()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(Noora.Colors.accent)
        .navigationTitle(isNew ? "New Rule" : "Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    isSaving = true
                    errorHandling.fireAndHandleError {
                        defer { isSaving = false }
                        try await viewModel.save(rule)
                        dismiss()
                    }
                }
                .disabled(isSaving)
            }
        }
        .task(id: rule.projects) {
            trackOptions = await viewModel.options(for: Condition.track.rawValue, in: rule)
            branchOptions = await viewModel.options(for: Condition.gitBranch.rawValue, in: rule)
        }
        .alert(
            "\(editing?.name ?? "") Contains",
            isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
            presenting: editing
        ) { condition in
            TextField("release/", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Done") {
                let value = text.trimmingCharacters(in: .whitespaces)
                let match: ServerNotificationRule.ValueMatch? = value.isEmpty ? nil : .contains(value)
                switch condition {
                case .track: rule.track = match
                case .gitBranch: rule.gitBranch = match
                }
            }
        } message: { condition in
            Text("Only notify when the preview's \(condition.name.lowercased()) contains this text, ignoring case.")
        }
    }

    private func conditionRow(
        _ condition: Condition,
        value: Binding<ServerNotificationRule.ValueMatch?>,
        options: [String]
    ) -> some View {
        LabeledContent(condition.name) {
            Menu {
                Picker(condition.name, selection: value) {
                    Text("Any \(condition.name)").tag(ServerNotificationRule.ValueMatch?.none)
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(ServerNotificationRule.ValueMatch?.some(.is(option)))
                    }
                    // Keeps a saved value that no recent preview used selectable.
                    if case let .is(current) = value.wrappedValue, !options.contains(current) {
                        Text(current).tag(ServerNotificationRule.ValueMatch?.some(.is(current)))
                    }
                }
                Divider()
                Button("Contains…", systemImage: "text.magnifyingglass") {
                    if case let .contains(current) = value.wrappedValue { text = current } else { text = "" }
                    editing = condition
                }
            } label: {
                HStack(spacing: 4) {
                    Text(value.wrappedValue?.label ?? "Any \(condition.name)")
                    Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.medium))
                }
                .foregroundStyle(Noora.Colors.accent)
            }
        }
    }
}

private struct ProjectsPicker: View {
    let projects: [String]
    @Binding var selection: [String]
    @State private var query = ""

    var body: some View {
        List {
            Section {
                row("Any Project", isOn: selection.isEmpty) { selection = [] }
            } footer: {
                Text("Includes projects you join later.")
            }
            Section("Projects") {
                ForEach(filtered, id: \.self) { project in
                    row(project, isOn: selection.contains(project)) {
                        if let index = selection.firstIndex(of: project) {
                            selection.remove(at: index)
                        } else {
                            selection.append(project)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query)
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [String] {
        query.isEmpty ? projects : projects.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Noora.Colors.accent)
                }
            }
        }
    }
}

/// Reads the current value and sends changes through `set`, reporting failures through `ErrorHandling`.
@MainActor
func asyncBinding<Value>(
    _ errorHandling: ErrorHandling,
    get: @escaping () -> Value,
    set: @escaping (Value) async throws -> Void
) -> Binding<Value> {
    Binding(
        get: get,
        set: { newValue in
            errorHandling.fireAndHandleError { try await set(newValue) }
        }
    )
}
