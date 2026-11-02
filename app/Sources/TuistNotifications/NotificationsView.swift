import SwiftUI
import TuistErrorHandling
import TuistNoora
import TuistServer
import UIKit

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
            permissionSection

            Section {
                Toggle(isOn: binding(\.pushNotifications.isActiveOnThisDevice, set: viewModel.setEnabledOnThisDevice)) {
                    label("Notifications on this device")
                }
                .disabled(viewModel.pushNotifications.permission != .authorized)
            } footer: {
                Text("Turning this off stops notifications on this device only.")
            }

            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.newPreviews.accounts.isEmpty {
                    Text("You don't belong to any accounts yet.")
                        .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                } else {
                    ForEach(viewModel.newPreviews.accounts) { account in
                        accountRow(account)
                        if !account.changedProjects.isEmpty {
                            exceptionsRow(account)
                        }
                    }
                }
            } header: {
                Text("New previews")
            } footer: {
                Text("These choices apply only to you. To change one project, use the bell on its previews.")
            }

            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.devices.isEmpty {
                    Text("No devices receive notifications yet.")
                        .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                } else {
                    ForEach(viewModel.sortedDevices) { device in
                        deviceRow(device)
                    }
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("Devices signed in to Tuist that can receive notifications. Swipe to remove a device.")
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.pushNotifications.refresh() }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            switch viewModel.pushNotifications.permission {
            case .unknown:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .notDetermined:
                VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
                    Text("Allow notifications to hear about new previews of your projects.")
                        .font(.body)
                        .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                    NooraButton(title: "Allow notifications") {
                        Task { await viewModel.pushNotifications.requestPermission() }
                    }
                }
                .padding(.vertical, Noora.Spacing.spacing2)
            case .denied:
                VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
                    Text("Notifications are turned off for Tuist. Turn them on in Settings to get notified on this device.")
                        .font(.body)
                        .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                    NooraButton(title: "Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                .padding(.vertical, Noora.Spacing.spacing2)
            case .authorized:
                HStack {
                    label("System permission")
                    Spacer()
                    Text("Allowed")
                        .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                }
            }
        }
    }

    private func accountRow(_ account: ServerNotificationPreferences.Account) -> some View {
        Toggle(isOn: asyncBinding(errorHandling) { account.enabled } set: { enabled in
            try await viewModel.setAccountEnabled(enabled, accountHandle: account.handle)
        }) {
            Text(account.handle)
            Text(
                account.handle == userHandle
                    ? "Previews of your personal projects"
                    : "Previews of this organization's projects"
            )
        }
    }

    /// The projects that don't follow the account, as chips whose ✕ makes them follow it again.
    private func exceptionsRow(_ account: ServerNotificationPreferences.Account) -> some View {
        HStack(spacing: Noora.Spacing.spacing4) {
            Text("Except")
                .font(.subheadline)
                .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: Noora.Spacing.spacing3) {
                    ForEach(account.changedProjects) { project in
                        exceptionChip(project, accountHandle: account.handle)
                    }
                }
                .padding(.vertical, Noora.Spacing.spacing1)
            }
            .scrollIndicators(.hidden)
        }
        .listRowSeparator(.hidden, edges: .top)
    }

    private func exceptionChip(_ project: ServerNotificationPreferences.Project, accountHandle: String) -> some View {
        let title = "\(project.handle) \(project.setting == .on ? "on" : "off")"
        return HStack(spacing: Noora.Spacing.spacing2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
            Button {
                errorHandling.fireAndHandleError {
                    try await viewModel.setProjectSetting(.default, accountHandle: accountHandle, projectHandle: project.handle)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Noora.Colors.surfaceLabelTertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Use account setting for \(project.handle)")
        }
        .padding(.leading, Noora.Spacing.spacing4)
        .padding(.trailing, Noora.Spacing.spacing3)
        .padding(.vertical, Noora.Spacing.spacing2)
        .background(Noora.Colors.surfaceBackgroundTertiary, in: Capsule())
        .overlay(Capsule().strokeBorder(Noora.Colors.neutralGray24Alpha, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private func deviceRow(_ device: ServerPushDevice) -> some View {
        let isThisDevice = viewModel.isThisDevice(device)
        return HStack(spacing: Noora.Spacing.spacing5) {
            Image(systemName: deviceSymbol(device))
                .font(.title3)
                .foregroundStyle(Noora.Colors.surfaceLabelSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Noora.Spacing.spacing1) {
                HStack(spacing: Noora.Spacing.spacing3) {
                    label(device.name ?? (device.platform == "android" ? "Android device" : "iOS device"))
                    if isThisDevice {
                        Text("This device")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Noora.Colors.accent)
                            .padding(.horizontal, Noora.Spacing.spacing3)
                            .padding(.vertical, Noora.Spacing.spacing1)
                            .background(Noora.Colors.buttonEnabledBackground, in: Capsule())
                    }
                }
                Text(
                    "\(device.platform == "android" ? "Android" : "iOS") · Last seen \(device.lastSeenAt.formatted(.relative(presentation: .named)))"
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

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
    }

    private func binding<Value>(
        _ keyPath: KeyPath<NotificationsViewModel, Value>,
        set: @escaping (Value) async throws -> Void
    ) -> Binding<Value> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { newValue in
                errorHandling.fireAndHandleError {
                    try await set(newValue)
                }
            }
        )
    }
}

/// Reads the current value and sends changes through `set`, reporting failures through `ErrorHandling`.
@MainActor
func asyncBinding<Value>(
    _ errorHandling: ErrorHandling,
    get: @escaping @Sendable () -> Value,
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
