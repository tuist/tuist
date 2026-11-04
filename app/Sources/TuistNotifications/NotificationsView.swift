import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistServer
import UIKit

/// Profile › Notifications. Notifications are opt-in: until the user turns them on, the screen only shows the switch.
public struct NotificationsView: View {
    @EnvironmentObject private var errorHandling: ErrorHandling
    @Environment(\.openURL) private var openURL
    @State private var viewModel: NotificationsViewModel
    /// The signed-in user's handle, which tells their personal account apart from organizations.
    private let userHandle: String

    public init(userHandle: String) {
        self.init(viewModel: NotificationsViewModel(), userHandle: userHandle)
    }

    init(viewModel: NotificationsViewModel, userHandle: String) {
        _viewModel = State(initialValue: viewModel)
        self.userHandle = userHandle
    }

    public var body: some View {
        List {
            if viewModel.isSupported {
                optInSection
                if viewModel.pushNotifications.permission == .denied {
                    deniedSection
                }
                if viewModel.isOptedIn {
                    newPreviewsSections
                        .disabled(viewModel.pushNotifications.permission == .denied)
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
        .background(Noora.Colors.surfaceBackgroundPrimary)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            do {
                try await viewModel.load()
            } catch {
                errorHandling.handle(error: error)
            }
        }
        .onChange(of: viewModel.pushNotifications.installationID) {
            // This device appears in the list once its registration finishes, after turning notifications on.
            Task { try? await viewModel.reloadDevices() }
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
            Text("Get notified on this device when new previews are out.")
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
    private var newPreviewsSections: some View {
        let accounts = viewModel.accountsWithProjects
        if viewModel.isLoading {
            Section("New Previews") {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } else if !viewModel.didLoad {
            EmptyView()
        } else if accounts.isEmpty {
            Section {} header: {
                Text("New Previews")
            } footer: {
                Text("You'll be able to choose notifications once you have a project.")
            }
        } else if accounts.count == 1, let account = accounts.first {
            // Most people belong to one account with projects, so its projects are shown right here.
            AccountNotificationsSections(viewModel: viewModel, account: account, header: "New Previews")
        } else {
            Section("New Previews") {
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountNotificationsView(viewModel: viewModel, accountHandle: account.handle)
                    } label: {
                        LabeledContent {
                            Text(account.summary)
                        } label: {
                            Text(account.handle)
                            Text(account.handle == userHandle ? "Personal" : "Organization")
                        }
                    }
                }
            }
        }
    }

    private var devicesSection: some View {
        Section {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
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
            Image(systemName: deviceSymbol(device))
                .font(.title3)
                .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Noora.Spacing.spacing1) {
                Text(device.name ?? "\(platform) device")
                    .font(.body)
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
                    errorHandling.fireAndHandleError {
                        try await viewModel.removeDevice(device)
                    }
                }
            }
        }
    }

    private func deviceSymbol(_ device: ServerPushDevice) -> String {
        if device.platform == "android" { return "smartphone" }
        return device.name?.hasPrefix("iPad") == true ? "ipad" : "iphone"
    }
}

/// One account's projects, opened from Notifications when several accounts have projects.
struct AccountNotificationsView: View {
    let viewModel: NotificationsViewModel
    let accountHandle: String

    var body: some View {
        List {
            if let account = viewModel.newPreviews.account(accountHandle) {
                AccountNotificationsSections(viewModel: viewModel, account: account, header: nil)
            }
        }
        .listStyle(.insetGrouped)
        .tint(Noora.Colors.accent)
        .background(Noora.Colors.surfaceBackgroundPrimary)
        .navigationTitle(accountHandle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The All Projects switch and a switch per project. A project whose switch differs from All Projects overrides it.
struct AccountNotificationsSections: View {
    @EnvironmentObject private var errorHandling: ErrorHandling
    @State private var searchText = ""
    let viewModel: NotificationsViewModel
    let account: ServerNotificationPreferences.Account
    let header: String?

    /// Long project lists get a search field.
    private static let searchThreshold = 8

    var body: some View {
        Section {
            Toggle(
                header == nil ? "All Projects" : "All Projects in \(account.handle)",
                isOn: asyncBinding(errorHandling) { account.enabled } set: { enabled in
                    try await viewModel.setAccountEnabled(enabled, accountHandle: account.handle)
                }
            )
            .disabled(viewModel.changesInFlight.contains(account.handle))
        } header: {
            if let header { Text(header) }
        } footer: {
            Text("New projects follow this setting.")
        }

        Section("Projects") {
            if account.projects.count > Self.searchThreshold {
                TextField("Search Projects", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            ForEach(filteredProjects) { project in
                Toggle(
                    project.handle,
                    isOn: asyncBinding(errorHandling) { project.enabled } set: { enabled in
                        try await viewModel.setProjectEnabled(
                            enabled,
                            accountHandle: account.handle,
                            projectHandle: project.handle
                        )
                    }
                )
                .disabled(viewModel.changesInFlight.contains("\(account.handle)/\(project.handle)"))
            }
        }
    }

    private var filteredProjects: [ServerNotificationPreferences.Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return account.projects }
        return account.projects.filter { $0.handle.localizedCaseInsensitiveContains(query) }
    }
}

extension ServerNotificationPreferences.Account {
    /// "On" or "Off" when every project agrees, "Custom" otherwise.
    var summary: String {
        if projects.allSatisfy(\.enabled) { return "On" }
        if projects.allSatisfy({ !$0.enabled }) { return "Off" }
        return "Custom"
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
            errorHandling.fireAndHandleError {
                try await set(newValue)
            }
        }
    )
}
