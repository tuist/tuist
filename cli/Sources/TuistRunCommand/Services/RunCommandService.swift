import FileSystem
import Foundation
import Noora
import Path
import TuistAndroid
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistServer
import TuistSupport

#if os(macOS)
    import struct TSCUtility.Version
    import TuistAutomation
    import TuistCore
    import TuistKit
    import TuistLoader
    import TuistSimulator
    import XcodeGraph
#endif

enum RunCommandServiceError: LocalizedError, Equatable {
    case invalidPreviewURL(String)
    case appNotFound(String)
    case appBundleNotFoundInArchive
    case apkNotFoundInArchive
    case missingPackageName
    case deviceNotFound(String)
    case noDevicesFound
    case schemeRunNotSupportedOnLinux
    #if os(macOS)
        case schemeNotFound(scheme: String, existing: [String])
        case schemeWithoutRunnableTarget(scheme: String)
        case invalidVersion(String)
        case workspaceNotFound(path: String)
        case missingFullHandle(displayName: String, specifier: String)
        case previewNotFound(displayName: String, specifier: String)
        case noCompatibleAppBuild(destination: String)
        case unspecifiedPlatform(target: String, platforms: [String])
    #endif

    var errorDescription: String? {
        switch self {
        case let .invalidPreviewURL(previewURL):
            return "The preview URL \(previewURL) is invalid."
        case let .appNotFound(url):
            return "The app at \(url) was not found."
        case .appBundleNotFoundInArchive:
            return "Could not find app bundle in the downloaded archive"
        case .apkNotFoundInArchive:
            return "Could not find APK in the downloaded archive"
        case .missingPackageName:
            return "The preview is missing a package name (bundle identifier). The APK cannot be launched without it."
        case let .deviceNotFound(device):
            return "Device '\(device)' not found among available devices or simulators"
        case .noDevicesFound:
            return "No devices found. Connect a device or start a simulator/emulator."
        case .schemeRunNotSupportedOnLinux:
            return "Running schemes and specifiers is only supported on macOS. Use a preview URL instead."
        #if os(macOS)
            case let .schemeNotFound(scheme, existing):
                return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
            case let .schemeWithoutRunnableTarget(scheme):
                return "The scheme \(scheme) cannot be run because it contains no runnable target."
            case let .invalidVersion(version):
                return "The version \(version) is not a valid version specifier."
            case let .workspaceNotFound(path):
                return "Workspace not found expected xcworkspace at \(path)"
            case let .missingFullHandle(displayName: displayName, specifier: specifier):
                return "We couldn't run the preview \(displayName)@\(specifier) because the full handle is missing. Make sure to specify it in your \(Constants.tuistManifestFileName) file."
            case let .previewNotFound(displayName: displayName, specifier: specifier):
                return "We could not find a preview for \(displayName)@\(specifier). You can create one by running tuist share \(displayName)."
            case let .noCompatibleAppBuild(destination):
                return "No compatible app build found for destination: \(destination)"
            case let .unspecifiedPlatform(target, platforms):
                return
                    "Only single platform targets supported. The target \(target) specifies multiple supported platforms (\(platforms.joined(separator: ", ")))."
        #endif
        }
    }
}

enum DestinationDevice: Equatable {
    case android(AndroidDevice)
    #if os(macOS)
        case simulator(SimulatorDeviceAndRuntime)
        case physical(PhysicalDevice)
    #endif
}

extension DestinationDevice {
    var isReady: Bool {
        switch self {
        case .android:
            return true
        #if os(macOS)
            case .physical:
                return true
            case let .simulator(sim):
                return !sim.device.isShutdown
        #endif
        }
    }
}

extension DestinationDevice: CustomStringConvertible {
    var description: String {
        switch self {
        case let .android(device):
            return "\(device.name) (Android\(device.type == .emulator ? " Emulator" : ""))"
        #if os(macOS)
            case let .physical(physicalDevice):
                return physicalDevice.name
            case let .simulator(simulatorDevice):
                let description =
                    "\(simulatorDevice.device.name), \((try? simulatorDevice.runtime.platform().caseValue) ?? "Unknown platform") \(simulatorDevice.runtime.version), \(simulatorDevice.device.udid)"
                if simulatorDevice.device.isShutdown {
                    return description
                } else {
                    return description + " (Booted)"
                }
        #endif
        }
    }
}

// swiftlint:disable:next type_body_length
struct RunCommandService {
    private let configLoader: ConfigLoading
    private let getPreviewService: GetPreviewServicing
    private let fileSystem: FileSysteming
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let fileArchiverFactory: FileArchivingFactorying
    private let adbController: AdbControlling

    #if os(macOS)
        private let generatorFactory: GeneratorFactorying
        private let buildGraphInspector: BuildGraphInspecting
        private let targetBuilder: TargetBuilding
        private let targetRunner: TargetRunning
        private let listPreviewsService: ListPreviewsServicing
        private let appBundleLoader: AppBundleLoading
        private let deviceController: DeviceControlling
        private let simulatorController: SimulatorControlling
    #endif

    init() {
        #if os(macOS)
            self.init(
                configLoader: ConfigLoader(),
                getPreviewService: GetPreviewService(),
                fileSystem: FileSystem(),
                remoteArtifactDownloader: RemoteArtifactDownloader(),
                fileArchiverFactory: FileArchivingFactory(),
                adbController: AdbController(),
                generatorFactory: GeneratorFactory(),
                buildGraphInspector: BuildGraphInspector(),
                targetBuilder: TargetBuilder(),
                targetRunner: TargetRunner(),
                listPreviewsService: ListPreviewsService(),
                appBundleLoader: AppBundleLoader(),
                deviceController: DeviceController(),
                simulatorController: SimulatorController()
            )
        #else
            self.init(
                configLoader: ConfigLoader(),
                getPreviewService: GetPreviewService(),
                fileSystem: FileSystem(),
                remoteArtifactDownloader: RemoteArtifactDownloader(),
                fileArchiverFactory: FileArchivingFactory(),
                adbController: AdbController()
            )
        #endif
    }

    #if os(macOS)
        init(
            configLoader: ConfigLoading,
            getPreviewService: GetPreviewServicing,
            fileSystem: FileSysteming,
            remoteArtifactDownloader: RemoteArtifactDownloading,
            fileArchiverFactory: FileArchivingFactorying,
            adbController: AdbControlling,
            generatorFactory: GeneratorFactorying,
            buildGraphInspector: BuildGraphInspecting,
            targetBuilder: TargetBuilding,
            targetRunner: TargetRunning,
            listPreviewsService: ListPreviewsServicing,
            appBundleLoader: AppBundleLoading,
            deviceController: DeviceControlling,
            simulatorController: SimulatorControlling
        ) {
            self.configLoader = configLoader
            self.getPreviewService = getPreviewService
            self.fileSystem = fileSystem
            self.remoteArtifactDownloader = remoteArtifactDownloader
            self.fileArchiverFactory = fileArchiverFactory
            self.adbController = adbController
            self.generatorFactory = generatorFactory
            self.buildGraphInspector = buildGraphInspector
            self.targetBuilder = targetBuilder
            self.targetRunner = targetRunner
            self.listPreviewsService = listPreviewsService
            self.appBundleLoader = appBundleLoader
            self.deviceController = deviceController
            self.simulatorController = simulatorController
        }
    #else
        init(
            configLoader: ConfigLoading,
            getPreviewService: GetPreviewServicing,
            fileSystem: FileSysteming,
            remoteArtifactDownloader: RemoteArtifactDownloading,
            fileArchiverFactory: FileArchivingFactorying,
            adbController: AdbControlling
        ) {
            self.configLoader = configLoader
            self.getPreviewService = getPreviewService
            self.fileSystem = fileSystem
            self.remoteArtifactDownloader = remoteArtifactDownloader
            self.fileArchiverFactory = fileArchiverFactory
            self.adbController = adbController
        }
    #endif

    func run(
        path _: String?,
        runnable: Runnable,
        device: String?
    ) async throws {
        switch runnable {
        case let .url(previewLink):
            try await runPreviewLink(
                previewLink,
                device: device
            )
        case .scheme, .specifier:
            throw RunCommandServiceError.schemeRunNotSupportedOnLinux
        }
    }

    #if os(macOS)
        // swiftlint:disable:next function_body_length
        func run(
            path: String?,
            runnable: Runnable,
            generate: Bool,
            clean: Bool,
            configuration: String?,
            device: String?,
            osVersion: String?,
            rosetta: Bool,
            arguments: [String]
        ) async throws {
            let device = arguments.firstIndex(of: "-destination").map { arguments[$0 + 1] } ?? device

            let runPath = try await Environment.current.pathRelativeToWorkingDirectory(path)

            let osVersion = try osVersion.map { versionString in
                guard let version = versionString.version() else {
                    throw RunCommandServiceError.invalidVersion(versionString)
                }
                return version
            }

            switch runnable {
            case let .url(previewLink):
                try await runPreviewLink(
                    previewLink,
                    device: device
                )
            case let .scheme(scheme):
                try await runScheme(
                    scheme,
                    path: runPath,
                    generate: generate,
                    clean: clean,
                    configuration: configuration,
                    device: device,
                    version: osVersion,
                    rosetta: rosetta,
                    arguments: arguments
                )
            case let .specifier(
                displayName: displayName,
                specifier: specifier
            ):
                let config = try await configLoader.loadConfig(path: runPath)
                guard let fullHandle = config.fullHandle
                else {
                    throw RunCommandServiceError.missingFullHandle(
                        displayName: displayName,
                        specifier: specifier
                    )
                }
                guard let preview = try await listPreviewsService.listPreviews(
                    displayName: displayName,
                    specifier: specifier,
                    supportedPlatforms: Platform.allCases.map(DestinationType.simulator),
                    page: 1,
                    pageSize: 1,
                    distinctField: nil,
                    fullHandle: fullHandle,
                    serverURL: config.url
                ).previews.first
                else {
                    throw RunCommandServiceError.previewNotFound(
                        displayName: displayName,
                        specifier: specifier
                    )
                }
                try await runPreviewLink(
                    preview.url,
                    device: device
                )
            }
        }
    #endif

    // MARK: - Preview link running

    // swiftlint:disable:next function_body_length
    private func runPreviewLink(
        _ previewLink: URL,
        device: String?
    ) async throws {
        guard let scheme = previewLink.scheme,
              let host = previewLink.host,
              let serverURL = URL(string: "\(scheme)://\(host)\(previewLink.port.map { ":" + String($0) } ?? "")"),
              previewLink.pathComponents.count > 4
        else { throw RunCommandServiceError.invalidPreviewURL(previewLink.absoluteString) }

        let preview = try await getPreviewService.getPreview(
            previewLink.lastPathComponent,
            fullHandle: "\(previewLink.pathComponents[1])/\(previewLink.pathComponents[2])",
            serverURL: serverURL
        )

        var destinationDevices: [DestinationDevice] = []

        if preview.supported_platforms.contains(.android) {
            let androidDevices = try await adbController.findAvailableDevices()
            destinationDevices.append(contentsOf: androidDevices.map(DestinationDevice.android))
        }

        #if os(macOS)
            if preview.supported_platforms.contains(where: { $0 != .android }) {
                let physicalDevices = try await deviceController.findAvailableDevices()
                destinationDevices.append(contentsOf: physicalDevices.map(DestinationDevice.physical))

                let simulators = try await appleSimulators(for: preview)
                destinationDevices.append(contentsOf: simulators.map(DestinationDevice.simulator))
            }
        #endif

        if let device {
            if let matched = destinationDevices.first(where: { matchesDevice($0, name: device) }) {
                try await runApp(
                    on: matched,
                    preview: preview,
                    previewLink: previewLink
                )
            } else {
                throw RunCommandServiceError.deviceNotFound(device)
            }
            return
        }

        guard !destinationDevices.isEmpty else {
            throw RunCommandServiceError.noDevicesFound
        }

        let readyDevices = destinationDevices.filter(\.isReady)
        if readyDevices.count == 1, let readyDevice = readyDevices.first {
            try await runApp(
                on: readyDevice,
                preview: preview,
                previewLink: previewLink
            )
        } else {
            let destination = Noora.current.singleChoicePrompt(
                title: nil,
                question: "Select a destination",
                options: destinationDevices,
                description: nil,
                collapseOnSelection: true,
                filterMode: .enabled,
                autoselectSingleChoice: true
            )
            try await runApp(
                on: destination,
                preview: preview,
                previewLink: previewLink
            )
        }
    }

    private func matchesDevice(_ device: DestinationDevice, name: String) -> Bool {
        switch device {
        case let .android(androidDevice):
            return androidDevice.name == name || androidDevice.id == name
        #if os(macOS)
            case let .physical(physicalDevice):
                return physicalDevice.name == name
            case let .simulator(simulatorDevice):
                return simulatorDevice.device.name == name
        #endif
        }
    }

    // MARK: - Dispatching to platform-specific run

    private func runApp(
        on destinationDevice: DestinationDevice,
        preview: Components.Schemas.Preview,
        previewLink: URL
    ) async throws {
        switch destinationDevice {
        case let .android(androidDevice):
            try await runAndroidApp(
                on: androidDevice,
                preview: preview,
                previewLink: previewLink
            )
        #if os(macOS)
            case let .physical(physicalDevice):
                let destination = DestinationType.device(physicalDevice.platform)
                let appBundle = try await downloadAppleAppBundle(
                    for: destination,
                    preview: preview,
                    previewLink: previewLink
                )
                try await runApp(
                    on: physicalDevice,
                    appBundle: appBundle
                )
            case let .simulator(simulatorDevice):
                let destination = DestinationType.simulator(try simulatorDevice.runtime.platform())
                let appBundle = try await downloadAppleAppBundle(
                    for: destination,
                    preview: preview,
                    previewLink: previewLink
                )
                try await runApp(
                    on: simulatorDevice.device,
                    appBundle: appBundle
                )
        #endif
        }
    }

    // MARK: - Android

    private func runAndroidApp(
        on androidDevice: AndroidDevice,
        preview: Components.Schemas.Preview,
        previewLink: URL
    ) async throws {
        guard let build = preview.builds.first(where: { $0.supported_platforms.contains(.android) })
        else { throw RunCommandServiceError.appNotFound(previewLink.absoluteString) }

        let displayName = preview.display_name ?? "app"
        guard let packageName = preview.bundle_identifier else {
            throw RunCommandServiceError.missingPackageName
        }

        try await Noora.current.progressStep(
            message: "Installing \(displayName) on \(androidDevice.name)",
            successMessage: "\(displayName) was successfully launched",
            errorMessage: nil,
            showSpinner: true
        ) { updateProgress in
            guard let buildURL = URL(string: build.url)
            else { throw RunCommandServiceError.appNotFound(previewLink.absoluteString) }
            let archivePath = try await remoteArtifactDownloader.download(url: buildURL)
            guard let archivePath else { throw RunCommandServiceError.appNotFound(previewLink.absoluteString) }

            let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()
            try await fileSystem.remove(archivePath)

            guard let apkPath = try await fileSystem.glob(directory: unarchivedDirectory, include: ["**/*.apk"])
                .collect()
                .first
            else { throw RunCommandServiceError.apkNotFoundInArchive }

            updateProgress("Installing \(displayName) on \(androidDevice.name)")
            try await adbController.installApp(at: apkPath, device: androidDevice)

            updateProgress("Launching \(displayName) on \(androidDevice.name)")
            try await adbController.launchApp(packageName: packageName, device: androidDevice)

            try await fileSystem.remove(unarchivedDirectory)
        }
    }

    // MARK: - macOS-only Apple methods

    #if os(macOS)
        private func appleSimulators(
            for preview: Components.Schemas.Preview
        ) async throws -> [SimulatorDeviceAndRuntime] {
            try await simulatorController.devicesAndRuntimes().filter { deviceAndRuntime in
                try preview.supported_platforms.contains { supportedPlatform in
                    switch supportedPlatform {
                    case .ios, .tvos, .watchos, .visionos, .macos, .android:
                        return false
                    case .ios_simulator:
                        return try deviceAndRuntime.runtime.platform() == .iOS
                    case .tvos_simulator:
                        return try deviceAndRuntime.runtime.platform() == .tvOS
                    case .watchos_simulator:
                        return try deviceAndRuntime.runtime.platform() == .watchOS
                    case .visionos_simulator:
                        return try deviceAndRuntime.runtime.platform() == .visionOS
                    }
                }
            }
            .sorted(by: {
                if $0.device.isShutdown != $1.device.isShutdown {
                    return !$0.device.isShutdown
                } else {
                    return $0.device.description < $1.device.description
                }
            })
        }

        private func previewSupportedPlatform(for destination: DestinationType) -> Components.Schemas.PreviewSupportedPlatform {
            switch destination {
            case let .device(platform):
                switch platform {
                case .iOS: return .ios
                case .macOS: return .macos
                case .tvOS: return .tvos
                case .watchOS: return .watchos
                case .visionOS: return .visionos
                }
            case let .simulator(platform):
                switch platform {
                case .iOS: return .ios_simulator
                case .macOS: return .macos
                case .tvOS: return .tvos_simulator
                case .watchOS: return .watchos_simulator
                case .visionOS: return .visionos_simulator
                }
            case .android:
                return .android
            }
        }

        private func downloadAppleAppBundle(
            for destination: DestinationType,
            preview: Components.Schemas.Preview,
            previewLink: URL
        ) async throws -> AppBundle {
            let targetPlatform = previewSupportedPlatform(for: destination)
            guard let buildURLString = preview.builds.first(where: { $0.supported_platforms.contains(targetPlatform) })?.url,
                  let buildURL = URL(string: buildURLString)
            else {
                throw RunCommandServiceError.noCompatibleAppBuild(destination: destination.description)
            }
            let archivePath = try await Noora.current.progressStep(message: "Downloading preview...") { _ in
                return try await remoteArtifactDownloader.download(url: buildURL)
            }
            guard let archivePath else { throw RunCommandServiceError.appNotFound(previewLink.absoluteString) }

            let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()
            try await fileSystem.remove(archivePath)

            guard let appBundlePath = try await
                fileSystem.glob(directory: unarchivedDirectory, include: ["*.app", "Payload/*.app"])
                .collect()
                .first
            else { throw RunCommandServiceError.appBundleNotFoundInArchive }
            return try await appBundleLoader.load(appBundlePath)
        }

        private func runApp(
            on physicalDevice: PhysicalDevice,
            appBundle: AppBundle
        ) async throws {
            try await Noora.current.progressStep(
                message: "Installing \(appBundle.infoPlist.name) on \(physicalDevice.name)",
                successMessage: "\(appBundle.infoPlist.name) was successfully launched",
                errorMessage: nil,
                showSpinner: true
            ) { updateProgress in
                try await deviceController.installApp(at: appBundle.path, device: physicalDevice)
                updateProgress("Launching \(appBundle.infoPlist.name) on \(physicalDevice.name)")
                try await deviceController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: physicalDevice)
            }
        }

        private func runApp(
            on simulatorDevice: SimulatorDevice,
            appBundle: AppBundle
        ) async throws {
            try await Noora.current.progressStep(
                message: "Installing \(appBundle.infoPlist.name) on \(simulatorDevice.name)",
                successMessage: "\(appBundle.infoPlist.name) was successfully launched",
                errorMessage: nil,
                showSpinner: true
            ) { updateProgress in
                let device = try simulatorController.booted(device: simulatorDevice)
                try simulatorController.installApp(at: appBundle.path, device: device)
                updateProgress("Launching \(appBundle.infoPlist.name) on \(simulatorDevice.name)")
                try await simulatorController.launchApp(
                    bundleId: appBundle.infoPlist.bundleId,
                    device: device,
                    arguments: []
                )
            }
        }

        // swiftlint:disable:next function_body_length
        private func runScheme(
            _ scheme: String,
            path: AbsolutePath,
            generate: Bool,
            clean: Bool,
            configuration: String?,
            device: String?,
            version: Version?,
            rosetta: Bool,
            arguments: [String]
        ) async throws {
            let graph: Graph
            let config = try await configLoader.loadConfig(path: path)
            let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
            let workspacePath = try await buildGraphInspector.workspacePath(directory: path)
            if generate || workspacePath == nil {
                Logger.current.notice("Generating project for running", metadata: .section)
                graph = try await generator.generateWithGraph(
                    path: path,
                    options: config.project.generatedProject?.generationOptions
                ).1
            } else {
                graph = try await generator.load(
                    path: path,
                    options: config.project.generatedProject?.generationOptions
                )
            }

            guard let workspacePath = try await buildGraphInspector.workspacePath(directory: path) else {
                throw RunCommandServiceError.workspaceNotFound(path: path.pathString)
            }

            let graphTraverser = GraphTraverser(graph: graph)
            let runnableSchemes = buildGraphInspector.runnableSchemes(graphTraverser: graphTraverser)

            Logger.current
                .debug("Found the following runnable schemes: \(runnableSchemes.map(\.name).joined(separator: ", "))")

            guard let scheme = runnableSchemes.first(where: { $0.name == scheme }) else {
                throw RunCommandServiceError.schemeNotFound(
                    scheme: scheme,
                    existing: runnableSchemes.map(\.name)
                )
            }

            guard let graphTarget = graphTraverser.schemeRunnableTarget(scheme: scheme) else {
                throw RunCommandServiceError.schemeWithoutRunnableTarget(scheme: scheme.name)
            }

            try targetRunner.assertCanRunTarget(graphTarget.target)

            guard let buildPlatform = graphTarget.target.destinations.first?.platform,
                  graphTarget.target.destinations.platforms.count == 1
            else {
                throw RunCommandServiceError.unspecifiedPlatform(
                    target: graphTarget.target.name,
                    platforms: graphTarget.target.supportedPlatforms.map(\.rawValue)
                )
            }

            try await targetBuilder.buildTarget(
                graphTarget,
                platform: buildPlatform,
                workspacePath: workspacePath,
                scheme: scheme,
                clean: clean,
                configuration: configuration,
                buildOutputPath: nil,
                derivedDataPath: nil,
                device: device,
                osVersion: version.map { XcodeGraph.Version(stringLiteral: $0.description) },
                rosetta: rosetta,
                graphTraverser: graphTraverser,
                passthroughXcodeBuildArguments: []
            )

            let minVersion: Version?
            if let deploymentTargetVersion = graphTarget.target.deploymentTargets.configuredVersions.first?.1 {
                minVersion = deploymentTargetVersion.version()
            } else {
                minVersion = scheme.targetDependencies()
                    .flatMap {
                        graphTraverser
                            .directLocalTargetDependencies(path: $0.projectPath, name: $0.name)
                            .flatMap(\.target.deploymentTargets.configuredVersions)
                            .compactMap { $0.1.version() }
                    }
                    .sorted()
                    .first
            }

            try await targetRunner.runTarget(
                graphTarget,
                platform: buildPlatform,
                workspacePath: workspacePath,
                schemeName: scheme.name,
                configuration: configuration,
                minVersion: minVersion,
                version: version,
                deviceName: device,
                arguments: arguments
            )
        }
    #endif
}
