import Foundation
import PathKit
import SwiftUI
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

enum SimulatorsViewModelError: FatalError, Equatable {
    case noSelectedSimulator
    case invalidDeeplink(String)
    case invalidDownloadURL(String)
    case appDownloadFailed(String)
    case appNotFound(SelectedDevice, [Platform])

    var description: String {
        switch self {
        case .noSelectedSimulator:
            return "To run a preview, you must have a simulator selected."
        case let .invalidDownloadURL(url):
            return "The preview download url \(url) is invalid."
        case let .appDownloadFailed(url):
            return "The app at \(url) was not found."
        case let .appNotFound(selectedDevice, platforms):
            let name: String
            let platform: String
            switch selectedDevice {
            case let .simulator(simulator):
                name = simulator.device.name
                platform = simulator.runtime.platform?.caseValue ?? simulator.runtime.name
            case let .device(device):
                name = device.name
                platform = device.platform.caseValue
            }
            return "Couldn't install the app for \(name). The \(name)'s platform is \(platform) and the app includes only the following platforms: \(platforms.map(\.caseValue).joined(separator: ", "))"
        case let .invalidDeeplink(deeplink):
            return "The preview deeplink \(deeplink) is invalid."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidDownloadURL:
            return .bug
        case .noSelectedSimulator, .appDownloadFailed, .appNotFound, .invalidDeeplink:
            return .abort
        }
    }
}

struct PinnedSimulatorsKey: AppStorageKey {
    static let key = "pinnedSimulators"
    static let defaultValue: [SimulatorDeviceAndRuntime] = []
}

struct SelectedDeviceKey: AppStorageKey {
    static let key = "selectedSimulator"
    static let defaultValue: SelectedDevice? = nil
}

enum SelectedDevice: Codable, Equatable {
    case simulator(SimulatorDeviceAndRuntime)
    case device(PhysicalDevice)
}

@Observable
final class DevicesViewModel: Sendable {
    private(set) var devices: [PhysicalDevice] = []

    private(set) var pinnedSimulators: [SimulatorDeviceAndRuntime] = []
    private(set) var unpinnedSimulators: [SimulatorDeviceAndRuntime] = []
    private(set) var selectedDevice: SelectedDevice?

    private let deviceController: DeviceControlling
    private let simulatorController: SimulatorControlling
    private let downloadPreviewService: DownloadPreviewServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let fileHandler: FileHandling
    private let appBundleLoader: AppBundleLoading
    private let appStorage: AppStoring

    init(
        deviceController: DeviceControlling = DeviceController(),
        simulatorController: SimulatorControlling = SimulatorController(),
        downloadPreviewService: DownloadPreviewServicing = DownloadPreviewService(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        remoteArtifactDownloader: RemoteArtifactDownloading = RemoteArtifactDownloader(),
        fileHandler: FileHandling = FileHandler.shared,
        appBundleLoader: AppBundleLoading = AppBundleLoader(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.deviceController = deviceController
        self.simulatorController = simulatorController
        self.downloadPreviewService = downloadPreviewService
        self.fileArchiverFactory = fileArchiverFactory
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.fileHandler = fileHandler
        self.appBundleLoader = appBundleLoader
        self.appStorage = appStorage
    }

    func selectSimulator(_ simulator: SimulatorDeviceAndRuntime) {
        selectedDevice = .simulator(simulator)
        try? appStorage.set(SelectedDeviceKey.self, value: selectedDevice)
    }

    func selectPhysicalDevice(_ device: PhysicalDevice) {
        selectedDevice = .device(device)
        try? appStorage.set(SelectedDeviceKey.self, value: selectedDevice)
    }

    func simulatorPinned(_ simulator: SimulatorDeviceAndRuntime, pinned: Bool) {
        if pinned {
            pinnedSimulators = (pinnedSimulators + [simulator]).sorted()
            unpinnedSimulators = unpinnedSimulators.filter { $0.device.udid != simulator.device.udid }
        } else {
            pinnedSimulators = pinnedSimulators.filter { $0.device.udid != simulator.device.udid }
            unpinnedSimulators = (unpinnedSimulators + [simulator]).sorted()
        }
        try? appStorage.set(PinnedSimulatorsKey.self, value: pinnedSimulators)
    }

    func onAppear() async throws {
        devices = try await deviceController.findAvailableDevices()

        let simulators = try await simulatorController.devicesAndRuntimes()
            .sorted()

        if let selectedDevice = try appStorage.get(SelectedDeviceKey.self) {
            self.selectedDevice = selectedDevice
        } else {
            selectedDevice = simulators.first(where: { !$0.device.isShutdown }).map { .simulator($0) }
        }

        pinnedSimulators = try appStorage.get(PinnedSimulatorsKey.self)

        unpinnedSimulators = Set(simulators)
            .subtracting(Set(pinnedSimulators))
            .map { $0 }
            .sorted()
    }

    func onChangeOfURL(_ url: URL?) async throws {
        guard let previewURL = url else { return }

        guard let selectedDevice else { throw SimulatorsViewModelError.noSelectedSimulator }

        let urlComponents = URLComponents(url: previewURL, resolvingAgainstBaseURL: false)
        guard let previewId = urlComponents?.queryItems?.first(where: { $0.name == "preview_id" })?.value,
              let fullHandle = urlComponents?.queryItems?.first(where: { $0.name == "full_handle" })?.value,
              let serverURLString = urlComponents?.queryItems?.first(where: { $0.name == "server_url" })?.value,
              let serverURL = URL(string: serverURLString)
        else { throw SimulatorsViewModelError.invalidDeeplink(previewURL.absoluteString) }

        let downloadURL = try await downloadPreviewService.downloadPreview(
            previewId,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        guard let downloadURL = URL(string: downloadURL) else { throw SimulatorsViewModelError.invalidDownloadURL(downloadURL) }

        guard let archivePath = try await remoteArtifactDownloader.download(url: downloadURL)
        else { throw SimulatorsViewModelError.appDownloadFailed(previewURL.absoluteString) }
        let fileUnarchiver = try fileArchiverFactory.makeFileUnarchiver(for: archivePath)
        let unarchivedDirectory = try fileUnarchiver.unzip()

        let apps = try await fileHandler.glob(unarchivedDirectory, glob: "*.app").concurrentMap {
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

        switch selectedDevice {
        case let .simulator(simulator):
            let bootedDevice = try simulatorController.booted(device: simulator.device, forced: true)
            try simulatorController.installApp(at: app.path, device: bootedDevice)
            try await simulatorController.launchApp(bundleId: app.infoPlist.bundleId, device: bootedDevice, arguments: [])
        case let .device(device):
            try await deviceController.installApp(at: app.path, device: device)
            try await deviceController.launchApp(bundleId: app.infoPlist.bundleId, device: device)
        }
    }
}

extension [SimulatorDeviceAndRuntime] {
    fileprivate func sorted() -> Self {
        sorted(by: {
            if $0.device.name == $1.device.name { return $0.runtime.name < $1.runtime.name }
            else { return $0.device.name < $1.device.name }
        })
    }
}
