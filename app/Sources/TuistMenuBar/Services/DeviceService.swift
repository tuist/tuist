import FileSystem
import Foundation
import Mockable
import Path
import TuistAndroid
import TuistAppStorage
import TuistAutomation
import TuistCore
import TuistLogging
import TuistProcess
import TuistServer
import TuistSimulator
import TuistSupport
import TuistXcodeBuildProducts

private enum DownloadedApp {
    case appBundle(AppBundle)
    case apk(path: AbsolutePath, packageName: String, displayName: String)

    var displayName: String {
        switch self {
        case let .appBundle(appBundle):
            return appBundle.infoPlist.name
        case let .apk(_, _, displayName):
            return displayName
        }
    }
}

enum DeviceServiceError: FatalError, Equatable {
    case appDownloadFailed(String)
    case appBundleNotFoundInArchive
    case apkNotFoundInArchive
    case missingPackageName(String)
    case noCompatibleMacBuild

    var description: String {
        switch self {
        case let .appDownloadFailed(id):
            return String(localized: "The app preview \(id) was not found.")
        case .appBundleNotFoundInArchive:
            return String(localized: "Could not find app bundle in the downloaded archive")
        case .apkNotFoundInArchive:
            return String(localized: "Could not find APK file in the downloaded archive")
        case let .missingPackageName(id):
            return String(localized: "The preview \(id) does not have a package name set.")
        case .noCompatibleMacBuild:
            return String(localized: "None of this preview's macOS builds can run on this Mac's processor.")
        }
    }

    var type: ErrorType {
        switch self {
        case .appDownloadFailed, .noCompatibleMacBuild:
            return .abort
        case .appBundleNotFoundInArchive, .apkNotFoundInArchive, .missingPackageName:
            return .bug
        }
    }
}

@Mockable
protocol DeviceServicing: ObservableObject {
    @MainActor func selectDevice(_ newDevice: Device?)
    var selectedDevice: Device? { get }
    var devices: [PhysicalDevice] { get }
    var simulators: [SimulatorDeviceAndRuntime] { get }
    var androidDevices: [AndroidDevice] { get }
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

    @Published
    private(set) var androidDevices: [AndroidDevice] = []

    private let taskStatusReporter: any TaskStatusReporting
    private let appStorage: AppStoring
    private let deviceController: DeviceControlling
    private let simulatorController: SimulatorControlling
    private let adbController: AdbControlling
    private let getPreviewService: GetPreviewServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let fileSystem: FileSysteming
    private let appBundleLoader: AppBundleLoading
    private let menuBarFocusService: MenuBarFocusServicing
    private let commandRunner: CommandRunning
    private let macPreviewsDirectory: AbsolutePath

    init(
        taskStatusReporter: any TaskStatusReporting,
        appStorage: AppStoring = AppStorage(),
        deviceController: DeviceControlling = DeviceController(),
        simulatorController: SimulatorControlling = SimulatorController(),
        adbController: AdbControlling = AdbController(),
        getPreviewService: GetPreviewServicing = GetPreviewService(),
        fileArchiverFactory: FileArchivingFactorying = FileArchivingFactory(),
        remoteArtifactDownloader: RemoteArtifactDownloading = RemoteArtifactDownloader(),
        fileSystem: FileSysteming = FileSystem(),
        appBundleLoader: AppBundleLoading = AppBundleLoader(),
        menuBarFocusService: MenuBarFocusServicing = MenuBarFocusService(),
        commandRunner: CommandRunning = CommandRunner(),
        macPreviewsDirectory: AbsolutePath? = nil
    ) {
        self.taskStatusReporter = taskStatusReporter
        self.appStorage = appStorage
        self.deviceController = deviceController
        self.simulatorController = simulatorController
        self.adbController = adbController
        self.getPreviewService = getPreviewService
        self.fileArchiverFactory = fileArchiverFactory
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.fileSystem = fileSystem
        self.appBundleLoader = appBundleLoader
        self.menuBarFocusService = menuBarFocusService
        self.commandRunner = commandRunner
        // swiftlint:disable:next force_try
        self.macPreviewsDirectory = macPreviewsDirectory ?? (try! AbsolutePath(
            validating: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tuist/Previews").path
        ))
    }

    @MainActor func selectDevice(_ newDevice: Device?) {
        selectedDevice = newDevice
        switch newDevice {
        case let .simulator(simulator):
            try? appStorage.set(SelectedDeviceKey.self, value: .simulator(id: simulator.id))
        case let .device(physicalDevice):
            try? appStorage.set(SelectedDeviceKey.self, value: .device(id: physicalDevice.id))
        case let .androidDevice(androidDevice):
            try? appStorage.set(SelectedDeviceKey.self, value: .androidDevice(id: androidDevice.id))
        case .thisMac:
            try? appStorage.set(SelectedDeviceKey.self, value: .thisMac)
        case .none:
            try? appStorage.set(SelectedDeviceKey.self, value: nil)
        }
    }

    func loadDevices() async throws {
        let devices = try await deviceController.findAvailableDevices()
        let simulators = try await simulatorController.devicesAndRuntimes().sorted()

        var androidDevices: [AndroidDevice] = []
        if await adbController.isAdbAvailable() {
            androidDevices = try await adbController.findAvailableDevices()
        }

        let selectedDevice =
            storedSelectedDevice(
                simulators: simulators,
                androidDevices: androidDevices
            ) ?? simulators.first(where: { !$0.device.isShutdown }).map { .simulator($0) }
        await MainActor.run {
            self.devices = devices
            self.simulators = simulators
            self.androidDevices = androidDevices
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

        // `platform=macos` runs on This Mac whatever the picker selection; otherwise the selected device is used.
        let platform = urlComponents?.queryItems?.first(where: { $0.name == "platform" })?.value
        try await launchPreview(
            with: previewId,
            fullHandle: fullHandle,
            serverURL: serverURL,
            device: platform == "macos" ? .thisMac : nil
        )
    }

    func launchPreview(
        with previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        try await launchPreview(with: previewId, fullHandle: fullHandle, serverURL: serverURL, device: nil)
    }

    private func launchPreview(
        with previewId: String,
        fullHandle: String,
        serverURL: URL,
        device: Device?
    ) async throws {
        guard let selectedDevice = device ?? selectedDevice else { throw SimulatorsViewModelError.noSelectedSimulator }

        let status = TaskStatus(
            displayName: String(localized: "Installing preview"),
            initialState: .preparing
        )

        await taskStatusReporter.add(
            status: status
        )

        do {
            let preview = try await ServerPreview(
                getPreviewService.getPreview(
                    previewId,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
            )

            let app = try await downloadApp(
                for: preview,
                selectedDevice: selectedDevice
            )

            await status.update(
                state: .running(message: String(localized: "Launching preview"), progress: .indeterminate)
            )

            try await launchApp(app, on: selectedDevice)

            let displayName = app.displayName
            if let gitCommitSHA = preview.gitCommitSHA {
                await status.markAsDone(
                    message: String(localized: "Installed \(displayName)@\(String(gitCommitSHA.prefix(7)))")
                )
            } else {
                await status.markAsDone(message: String(localized: "Installed \(displayName)"))
            }
        } catch {
            await status.markAsDone(message: String(localized: "Installation failed"))
            throw error
        }
    }

    private func downloadApp(
        for preview: ServerPreview,
        selectedDevice: Device
    ) async throws -> DownloadedApp {
        if selectedDevice == .thisMac {
            return .appBundle(try await installMacApp(for: preview))
        }
        let destination: DestinationType
        switch selectedDevice {
        case let .device(physicalDevice):
            destination = .device(physicalDevice.platform)
        case let .simulator(simulator):
            destination = .simulator(try simulator.runtime.platform())
        case .androidDevice:
            destination = .android
        case .thisMac:
            destination = .device(.macOS)
        }
        guard let build = preview.appBuilds.first(where: { $0.supportedPlatforms.contains(destination) })
        else {
            throw SimulatorsViewModelError.appNotFound(
                selectedDevice,
                preview.appBuilds.flatMap(\.supportedPlatforms)
            )
        }

        guard let archivePath = try await remoteArtifactDownloader.download(url: build.url)
        else { throw DeviceServiceError.appDownloadFailed(preview.id) }
        let fileUnarchiver = try fileArchiverFactory.makeFileUnarchiver(for: archivePath)
        let unarchivedDirectory = try await fileUnarchiver.unzip()

        switch selectedDevice {
        case .device, .simulator:
            guard let appPath = try await fileSystem.glob(
                directory: unarchivedDirectory, include: ["*.app", "Payload/*.app"]
            )
            .collect()
            .first
            else { throw DeviceServiceError.appBundleNotFoundInArchive }

            return .appBundle(try await appBundleLoader.load(appPath))

        case .thisMac:
            throw DeviceServiceError.appBundleNotFoundInArchive

        case .androidDevice:
            guard let packageName = preview.bundleIdentifier else {
                throw DeviceServiceError.missingPackageName(preview.id)
            }
            guard let apkPath = try await fileSystem.glob(
                directory: unarchivedDirectory, include: ["**/*.apk"]
            )
            .collect()
            .first
            else { throw DeviceServiceError.apkNotFoundInArchive }

            return .apk(
                path: apkPath,
                packageName: packageName,
                displayName: preview.displayName ?? packageName
            )
        }
    }

    /// Installs the first macOS app bundle build this Mac's processor can run, reusing a build installed earlier.
    private func installMacApp(for preview: ServerPreview) async throws -> AppBundle {
        let builds = preview.appBuilds.filter {
            $0.type == .appBundle && $0.supportedPlatforms.contains(.device(.macOS))
        }
        guard !builds.isEmpty else {
            throw SimulatorsViewModelError.appNotFound(.thisMac, preview.appBuilds.flatMap(\.supportedPlatforms))
        }
        for build in builds {
            let appBundle = try await installedMacApp(for: build, preview: preview)
            guard let executableName = appBundle.infoPlist.executableName else {
                throw DeviceServiceError.appBundleNotFoundInArchive
            }
            let executable = appBundle.path.appending(components: "Contents", "MacOS", executableName)
            if (try? ExecutablePreviewTarget.read(at: executable.url).isCompatible) == true {
                return appBundle
            }
        }
        throw DeviceServiceError.noCompatibleMacBuild
    }

    private func installedMacApp(for build: AppBuild, preview: ServerPreview) async throws -> AppBundle {
        // Build IDs come from the server, so they're hashed rather than used as a path component.
        let buildDirectory = macPreviewsDirectory.appending(component: build.id.md5)
        // A build never changes, so an installed copy is reused instead of replacing one that may be running.
        if let installedAppPath = try await appPath(in: buildDirectory) {
            return try await appBundleLoader.load(installedAppPath)
        }

        guard let archivePath = try await remoteArtifactDownloader.download(url: build.url)
        else { throw DeviceServiceError.appDownloadFailed(preview.id) }
        let unarchivedDirectory = try await fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()
        guard let appPath = try await appPath(in: unarchivedDirectory)
        else { throw DeviceServiceError.appBundleNotFoundInArchive }

        // Publish the build with a same-filesystem rename so a failed or concurrent install never leaves half an app.
        let staging = macPreviewsDirectory.appending(component: UUID().uuidString)
        try await fileSystem.makeDirectory(at: staging)
        do {
            try await fileSystem.move(from: appPath, to: staging.appending(component: appPath.basename))
            if try await fileSystem.exists(buildDirectory) {
                try await fileSystem.remove(buildDirectory)
            }
            if rename(staging.pathString, buildDirectory.pathString) != 0 {
                let code = errno
                guard code == EEXIST || code == ENOTEMPTY else {
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                try await fileSystem.remove(staging)
            }
        } catch {
            try? await fileSystem.remove(staging)
            throw error
        }
        guard let installedAppPath = try await self.appPath(in: buildDirectory)
        else { throw DeviceServiceError.appBundleNotFoundInArchive }
        return try await appBundleLoader.load(installedAppPath)
    }

    private func appPath(in directory: AbsolutePath) async throws -> AbsolutePath? {
        guard try await fileSystem.exists(directory) else { return nil }
        return try await fileSystem.glob(directory: directory, include: ["*.app"]).collect().first
    }

    private func launchApp(
        _ app: DownloadedApp,
        on device: Device
    ) async throws {
        switch (app, device) {
        case let (.appBundle(appBundle), .simulator(simulator)):
            let bootedDevice = try await simulatorController.booted(
                device: simulator.device, forced: true
            )
            try await simulatorController.installApp(at: appBundle.path, device: bootedDevice)
            try await simulatorController.launchApp(
                bundleId: appBundle.infoPlist.bundleId, device: bootedDevice, arguments: []
            )
        case let (.appBundle(appBundle), .device(device)):
            try await deviceController.installApp(at: appBundle.path, device: device)
            try await deviceController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: device)
        case let (.apk(apkPath, packageName, _), .androidDevice(androidDevice)):
            try await adbController.installApp(at: apkPath, device: androidDevice)
            try await adbController.launchApp(packageName: packageName, device: androidDevice)
        case let (.appBundle(appBundle), .thisMac):
            _ = try await commandRunner.run(
                arguments: ["/usr/bin/open", "-n", appBundle.path.pathString]
            ).concatenatedString()
        default:
            break
        }
    }

    private func storedSelectedDevice(
        simulators: [SimulatorDeviceAndRuntime],
        androidDevices: [AndroidDevice]
    ) -> Device? {
        guard let selectedDevice = try? appStorage.get(SelectedDeviceKey.self) else { return nil }
        switch selectedDevice {
        case let .simulator(id):
            return simulators.first(where: { $0.id == id }).map { .simulator($0) }
        case let .device(id):
            return devices.first(where: { $0.id == id }).map { .device($0) }
        case let .androidDevice(id):
            return androidDevices.first(where: { $0.id == id }).map { .androidDevice($0) }
        case .thisMac:
            return .thisMac
        }
    }
}
