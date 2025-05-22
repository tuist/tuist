import FileSystem
import Foundation
import Mockable
import TuistAutomation
import TuistCore
import TuistServerCore
import TuistSupport

enum DeviceServiceError: FatalError, Equatable {
    case appDownloadFailed(String)

    var description: String {
        switch self {
        case let .appDownloadFailed(id):
            return "The app preview \(id) was not found."
        }
    }

    var type: ErrorType {
        switch self {
        case .appDownloadFailed:
            return .abort
        }
    }
}

@Mockable
protocol DeviceServicing: ObservableObject {
    @MainActor func selectDevice(_ newDevice: Device?)
    var selectedDevice: Device? { get }
    var devices: [PhysicalDevice] { get }
    var simulators: [SimulatorDeviceAndRuntime] { get }
    func launchPreview(
        with previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
    func launchPreviewDeeplink(with url: URL) async throws
    func loadDevices() async throws
}

final class DeviceService: DeviceServicing {
    @Published
    private(set) var selectedDevice: Device?

    @Published
    private(set) var devices: [PhysicalDevice] = []

    @Published
    private(set) var simulators: [SimulatorDeviceAndRuntime] = []

    private let taskStatusReporter: any TaskStatusReporting
    private let appStorage: AppStoring
    private let deviceController: DeviceControlling
    private let simulatorController: SimulatorControlling
    private let getPreviewService: GetPreviewServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let fileSystem: FileSysteming
    private let appBundleLoader: AppBundleLoading
    private let menuBarFocusService: MenuBarFocusServicing

    init(
        taskStatusReporter: any TaskStatusReporting,
        appStorage: AppStoring = AppStorage(),
        deviceController: DeviceControlling = DeviceController(),
        simulatorController: SimulatorControlling = SimulatorController(),
        getPreviewService: GetPreviewServicing = GetPreviewService(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        remoteArtifactDownloader: RemoteArtifactDownloading = RemoteArtifactDownloader(),
        fileSystem: FileSysteming = FileSystem(),
        appBundleLoader: AppBundleLoading = AppBundleLoader(),
        menuBarFocusService: MenuBarFocusServicing = MenuBarFocusService()
    ) {
        self.taskStatusReporter = taskStatusReporter
        self.appStorage = appStorage
        self.deviceController = deviceController
        self.simulatorController = simulatorController
        self.getPreviewService = getPreviewService
        self.fileArchiverFactory = fileArchiverFactory
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.fileSystem = fileSystem
        self.appBundleLoader = appBundleLoader
        self.menuBarFocusService = menuBarFocusService
    }

    @MainActor func selectDevice(_ newDevice: Device?) {
        selectedDevice = newDevice
        switch newDevice {
        case let .simulator(simulator):
            try? appStorage.set(SelectedDeviceKey.self, value: .simulator(id: simulator.id))
        case let .device(physicalDevice):
            try? appStorage.set(SelectedDeviceKey.self, value: .device(id: physicalDevice.id))
        case .none:
            try? appStorage.set(SelectedDeviceKey.self, value: nil)
        }
    }

    func loadDevices() async throws {
        let devices = try await deviceController.findAvailableDevices()
        let simulators = try await simulatorController.devicesAndRuntimes().sorted()

        let selectedDevice =
            storedSelectedDevice(
                simulators: simulators
            ) ?? simulators.first(where: { !$0.device.isShutdown }).map { .simulator($0) }
        await MainActor.run {
            self.devices = devices
            self.simulators = simulators
            self.selectedDevice = selectedDevice
        }
    }

    func launchPreviewDeeplink(with previewDeeplinkURL: URL) async throws {
        await menuBarFocusService.focus()
        let urlComponents = URLComponents(url: previewDeeplinkURL, resolvingAgainstBaseURL: false)
        guard let previewId = urlComponents?.queryItems?.first(where: { $0.name == "preview_id" })?
            .value,
            let fullHandle = urlComponents?.queryItems?.first(where: { $0.name == "full_handle" })?
            .value,
            let serverURLString = urlComponents?.queryItems?.first(where: {
                $0.name == "server_url"
            })?.value,
            let serverURL = URL(string: serverURLString)
        else { throw SimulatorsViewModelError.invalidDeeplink(previewDeeplinkURL.absoluteString) }

        try await launchPreview(
            with: previewId,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
    }

    func launchPreview(
        with previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        guard let selectedDevice else { throw SimulatorsViewModelError.noSelectedSimulator }

        let status = TaskStatus(
            displayName: "Installing preview",
            initialState: .preparing
        )

        await taskStatusReporter.add(
            status: status
        )

        do {
            let preview = try await getPreviewService.getPreview(
                previewId,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            let app = try await downloadApp(
                for: preview,
                selectedDevice: selectedDevice
            )

            await status.update(
                state: .running(message: "Launching preview", progress: .indeterminate)
            )

            try await launchApp(app, on: selectedDevice)
            if let gitCommitSHA = preview.gitCommitSHA {
                await status.markAsDone(
                    message: "Installed \(app.infoPlist.name)@\(gitCommitSHA.prefix(7))"
                )
            } else {
                await status.markAsDone(message: "Installed \(app.infoPlist.name)")
            }
        } catch {
            await status.markAsDone(message: "Installation failed")
            throw error
        }
    }

    private func downloadApp(
        for preview: Preview,
        selectedDevice: Device
    ) async throws -> AppBundle {
        guard let archivePath = try await remoteArtifactDownloader.download(url: preview.url)
        else { throw DeviceServiceError.appDownloadFailed(preview.id) }
        let fileUnarchiver = try fileArchiverFactory.makeFileUnarchiver(for: archivePath)
        let unarchivedDirectory = try fileUnarchiver.unzip()

        let apps = try await fileSystem.glob(
            directory: unarchivedDirectory, include: ["*.app", "Payload/*.app"]
        ).collect()
            .concurrentMap {
                try await self.appBundleLoader.load($0)
            }

        guard let app = apps.first(
            where: {
                $0.infoPlist.supportedPlatforms.contains(
                    where: {
                        switch $0 {
                        case let .device(platform):
                            switch selectedDevice {
                            case let .device(device):
                                return device.platform == platform
                            case .simulator:
                                return false
                            }
                        case let .simulator(platform):
                            switch selectedDevice {
                            case .device:
                                return false
                            case let .simulator(simulator):
                                return simulator.runtime.platform == platform
                            }
                        }
                    }
                )
            }
        )
        else {
            throw SimulatorsViewModelError.appNotFound(
                selectedDevice,
                apps.flatMap(\.infoPlist.supportedPlatforms).compactMap {
                    switch $0 {
                    case .device:
                        return nil
                    case let .simulator(platform):
                        return platform
                    }
                }
            )
        }

        return app
    }

    private func launchApp(
        _ app: AppBundle,
        on device: Device
    ) async throws {
        switch device {
        case let .simulator(simulator):
            let bootedDevice = try simulatorController.booted(
                device: simulator.device, forced: true
            )
            try simulatorController.installApp(at: app.path, device: bootedDevice)
            try await simulatorController.launchApp(
                bundleId: app.infoPlist.bundleId, device: bootedDevice, arguments: []
            )
        case let .device(device):
            try await deviceController.installApp(at: app.path, device: device)
            try await deviceController.launchApp(bundleId: app.infoPlist.bundleId, device: device)
        }
    }

    private func storedSelectedDevice(
        simulators: [SimulatorDeviceAndRuntime]
    ) -> Device? {
        guard let selectedDevice = try? appStorage.get(SelectedDeviceKey.self) else { return nil }
        switch selectedDevice {
        case let .simulator(id):
            return simulators.first(where: { $0.id == id }).map { .simulator($0) }
        case let .device(id):
            return devices.first(where: { $0.id == id }).map { .device($0) }
        }
    }
}
