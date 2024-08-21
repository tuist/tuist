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
    case appNotFound(SimulatorDeviceAndRuntime, [Platform])

    var description: String {
        switch self {
        case .noSelectedSimulator:
            return "To run a preview, you must have a simulator selected."
        case let .invalidDownloadURL(url):
            return "The preview download url \(url) is invalid."
        case let .appDownloadFailed(url):
            return "The app at \(url) was not found."
        case let .appNotFound(selectedSimulator, platforms):
            return "Couldn't install the app for \(selectedSimulator.device.name). The \(selectedSimulator.device.name)'s platform is \(selectedSimulator.runtime.platform?.caseValue ?? selectedSimulator.runtime.name) and the app includes only the following platforms: \(platforms.map(\.caseValue).joined(separator: ", "))"
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

struct SelectedSimulatorKey: AppStorageKey {
    static let key = "selectedSimulator"
    static let defaultValue: SimulatorDeviceAndRuntime? = nil
}

@Observable
final class SimulatorsViewModel: Sendable {
    private(set) var pinnedSimulators: [SimulatorDeviceAndRuntime] = []
    private(set) var unpinnedSimulators: [SimulatorDeviceAndRuntime] = []
    private(set) var selectedSimulator: SimulatorDeviceAndRuntime?

    private let simulatorController: SimulatorControlling
    private let downloadPreviewService: DownloadPreviewServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let fileHandler: FileHandling
    private let appBundleLoader: AppBundleLoading
    private let appStorage: AppStoring

    init(
        simulatorController: SimulatorControlling = SimulatorController(),
        downloadPreviewService: DownloadPreviewServicing = DownloadPreviewService(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        remoteArtifactDownloader: RemoteArtifactDownloading = RemoteArtifactDownloader(),
        fileHandler: FileHandling = FileHandler.shared,
        appBundleLoader: AppBundleLoading = AppBundleLoader(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.simulatorController = simulatorController
        self.downloadPreviewService = downloadPreviewService
        self.fileArchiverFactory = fileArchiverFactory
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.fileHandler = fileHandler
        self.appBundleLoader = appBundleLoader
        self.appStorage = appStorage
    }

    func selectSimulator(_ simulator: SimulatorDeviceAndRuntime) {
        selectedSimulator = simulator
        try? appStorage.set(SelectedSimulatorKey.self, value: simulator)
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
        let simulators = try await simulatorController.devicesAndRuntimes()
            .sorted()

        if let selectedSimulator = try appStorage.get(SelectedSimulatorKey.self) {
            self.selectedSimulator = selectedSimulator
        } else {
            selectedSimulator = simulators.first(where: { !$0.device.isShutdown })
        }

        pinnedSimulators = try appStorage.get(PinnedSimulatorsKey.self)

        unpinnedSimulators = Set(simulators)
            .subtracting(Set(pinnedSimulators))
            .map { $0 }
            .sorted()
    }

    func onChangeOfURL(_ url: URL?) async throws {
        guard let previewURL = url else { return }

        guard let selectedSimulator else { throw SimulatorsViewModelError.noSelectedSimulator }

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
                        case .device:
                            return false
                        case let .simulator(platform):
                            return selectedSimulator.runtime.platform == platform
                        }
                    }
                )
            }
        )
        else {
            throw SimulatorsViewModelError.appNotFound(
                selectedSimulator,
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

        let bootedDevice = try simulatorController.booted(device: selectedSimulator.device, forced: true)
        try simulatorController.installApp(at: app.path, device: bootedDevice)
        try simulatorController.launchApp(bundleId: app.infoPlist.bundleId, device: bootedDevice, arguments: [])
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
