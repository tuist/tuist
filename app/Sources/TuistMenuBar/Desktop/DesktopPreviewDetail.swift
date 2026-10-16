import SwiftUI
import TuistAuthentication
import TuistServer

struct DesktopPreviewDetail: View {
    let preview: ServerPreview
    let fullHandle: String
    @EnvironmentObject private var deviceService: DeviceService
    @EnvironmentObject private var errorHandling: ErrorHandling
    @State private var isLaunching = false
    @State private var isRefreshingDevices = false

    private struct RunDestination: Identifiable {
        let id: String
        let name: String
        let device: Device
    }

    private var destinations: [RunDestination] {
        deviceService.devices.filter { $0.connectionState == .connected }.map {
            RunDestination(id: "device:\($0.id)", name: $0.name, device: .device($0))
        } + deviceService.simulators.map {
            RunDestination(
                id: "simulator:\($0.id)",
                name: "\($0.device.name) · \($0.runtime.name)",
                device: .simulator($0)
            )
        } + deviceService.androidDevices.map {
            RunDestination(id: "android:\($0.id)", name: $0.name, device: .androidDevice($0))
        }
    }

    private var selectedDestinationID: String? {
        destinations.first { $0.device == deviceService.selectedDevice }?.id
    }

    private var canRun: Bool {
        guard let device = deviceService.selectedDevice, let destination = try? device.destinationType() else { return false }
        return preview.appBuilds.contains { $0.supportedPlatforms.contains(destination) }
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    DesktopPreviewIcon(url: preview.iconURL)
                        .frame(width: 80, height: 80)
                    Text(preview.displayName ?? "Preview")
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    Text(fullHandle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Section("Run Preview") {
                Picker("Run on", selection: Binding(
                    get: { selectedDestinationID },
                    set: { id in
                        deviceService.selectDevice(destinations.first { $0.id == id }?.device)
                    }
                )) {
                    Text("Choose a device").tag(String?.none)
                    ForEach(destinations) { destination in
                        Text(destination.name).tag(Optional(destination.id))
                    }
                }
                .disabled(isLaunching)

                HStack {
                    Button("Refresh Devices", systemImage: "arrow.clockwise") {
                        isRefreshingDevices = true
                        errorHandling.fireAndHandleError {
                            defer { isRefreshingDevices = false }
                            try await deviceService.loadDevices()
                        }
                    }
                    .disabled(isRefreshingDevices || isLaunching)
                    Spacer()
                    Button("Run Preview", systemImage: "play.fill", action: run)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canRun || isLaunching)
                }

                if isLaunching {
                    ProgressView("Installing preview…")
                } else if deviceService.selectedDevice != nil, !canRun {
                    Text("This preview doesn't include a build for the selected device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                LabeledContent("Created") {
                    Text(preview.insertedAt, format: .dateTime)
                }
                if let version = preview.version {
                    LabeledContent("Version", value: version.description)
                }
                if let bundleIdentifier = preview.bundleIdentifier {
                    LabeledContent("Bundle Identifier", value: bundleIdentifier)
                }
                if let track = preview.track, !track.isEmpty {
                    LabeledContent("Track", value: track)
                }
                if let branch = preview.gitBranch {
                    LabeledContent("Branch", value: branch)
                }
                if let commit = preview.gitCommitSHA {
                    LabeledContent("Commit", value: String(commit.prefix(7)))
                }
                LabeledContent("Platforms", value: preview.supportedPlatforms.map(\.description).joined(separator: ", "))
            }
            .textSelection(.enabled)
        }
        .formStyle(.grouped)
    }

    private func run() {
        isLaunching = true
        errorHandling.fireAndHandleError {
            defer { isLaunching = false }
            try await deviceService.launchPreview(
                with: preview.id,
                fullHandle: fullHandle,
                serverURL: AppServerEnvironmentService().url()
            )
        }
    }
}
