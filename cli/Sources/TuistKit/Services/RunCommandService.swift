import FileSystem
import Foundation
import Noora
import Path
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSimulator
import TuistSupport
import XcodeGraph

enum RunCommandServiceError: LocalizedError, Equatable {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutRunnableTarget(scheme: String)
    case invalidVersion(String)
    case workspaceNotFound(path: String)
    case invalidPreviewURL(String)
    case appNotFound(String)
    case missingFullHandle(displayName: String, specifier: String)
    case previewNotFound(displayName: String, specifier: String)
    case noCompatibleAppBuild(destination: String)
    case appBundleNotFoundInArchive
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .schemeNotFound(scheme, existing):
            return "Couldn't find scheme \(scheme). The available schemes are: \(existing.joined(separator: ", "))."
        case let .schemeWithoutRunnableTarget(scheme):
            return "The scheme \(scheme) cannot be run because it contains no runnable target."
        case let .invalidVersion(version):
            return "The version \(version) is not a valid version specifier."
        case let .workspaceNotFound(path):
            return "Workspace not found expected xcworkspace at \(path)"
        case let .invalidPreviewURL(previewURL):
            return "The preview URL \(previewURL) is invalid."
        case let .appNotFound(url):
            return "The app at \(url) was not found."
        case let .missingFullHandle(displayName: displayName, specifier: specifier):
            return "We couldn't run the preview \(displayName)@\(specifier) because the full handle is missing. Make sure to specify it in your \(Constants.tuistManifestFileName) file."
        case let .previewNotFound(displayName: displayName, specifier: specifier):
            return "We could not find a preview for \(displayName)@\(specifier). You can create one by running tuist share \(displayName)."
        case let .noCompatibleAppBuild(destination):
            return "No compatible app build found for destination: \(destination)"
        case .appBundleNotFoundInArchive:
            return "Could not find app bundle in the downloaded archive"
        case let .deviceNotFound(device):
            return "Device '\(device)' not found among available devices or simulators"
        }
    }
}

// swiftlint:disable:next type_body_length
struct RunCommandService {
    private let generatorFactory: GeneratorFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding
    private let targetRunner: TargetRunning
    private let configLoader: ConfigLoading
    private let getPreviewService: GetPreviewServicing
    private let listPreviewsService: ListPreviewsServicing
    private let fileSystem: FileSysteming
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let appBundleLoader: AppBundleLoading
    private let fileArchiverFactory: FileArchivingFactorying
    private let deviceController: DeviceControlling
    private let simulatorController: SimulatorControlling

    init() {
        self.init(
            generatorFactory: GeneratorFactory(),
            buildGraphInspector: BuildGraphInspector(),
            targetBuilder: TargetBuilder(),
            targetRunner: TargetRunner(),
            configLoader: ConfigLoader(manifestLoader: ManifestLoader()),
            getPreviewService: GetPreviewService(),
            listPreviewsService: ListPreviewsService(),
            fileSystem: FileSystem(),
            remoteArtifactDownloader: RemoteArtifactDownloader(),
            appBundleLoader: AppBundleLoader(),
            fileArchiverFactory: FileArchivingFactory(),
            deviceController: DeviceController(),
            simulatorController: SimulatorController()
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        buildGraphInspector: BuildGraphInspecting,
        targetBuilder: TargetBuilding,
        targetRunner: TargetRunning,
        configLoader: ConfigLoading,
        getPreviewService: GetPreviewServicing,
        listPreviewsService: ListPreviewsServicing,
        fileSystem: FileSystem,
        remoteArtifactDownloader: RemoteArtifactDownloading,
        appBundleLoader: AppBundleLoading,
        fileArchiverFactory: FileArchivingFactorying,
        deviceController: DeviceControlling,
        simulatorController: SimulatorControlling
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.targetRunner = targetRunner
        self.configLoader = configLoader
        self.getPreviewService = getPreviewService
        self.listPreviewsService = listPreviewsService
        self.fileSystem = fileSystem
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.appBundleLoader = appBundleLoader
        self.fileArchiverFactory = fileArchiverFactory
        self.deviceController = deviceController
        self.simulatorController = simulatorController
    }

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

        let runPath: AbsolutePath
        if let path {
            runPath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            runPath = FileHandler.shared.currentPath
        }

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
                device: device,
                version: osVersion
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
                // `tuist run` currently supports only simulator builds
                supportedPlatforms: Platform.allCases.map(DestinationType.simulator),
                page: 1,
                pageSize: 1,
                distinctField: nil,
                fullHandle: fullHandle,
                serverURL: config.url
            ).previews.first else { throw RunCommandServiceError.previewNotFound(displayName: displayName, specifier: specifier) }
            try await runPreviewLink(
                preview.url,
                device: device,
                version: osVersion
            )
        }
    }

    private func runPreviewLink(
        _ previewLink: URL,
        device: String?,
        version _: Version?
    ) async throws {
        guard let scheme = previewLink.scheme,
              let host = previewLink.host,
              let serverURL = URL(string: "\(scheme)://\(host)\(previewLink.port.map { ":" + String($0) } ?? "")"),
              previewLink.pathComponents.count > 4 // We expect at least four path components
        else { throw RunCommandServiceError.invalidPreviewURL(previewLink.absoluteString) }
        let preview = try await getPreviewService.getPreview(
            previewLink.lastPathComponent,
            fullHandle: "\(previewLink.pathComponents[1])/\(previewLink.pathComponents[2])",
            serverURL: serverURL
        )
        let devices = try await deviceController.findAvailableDevices()
        let simulators = try await simulators(for: preview)
        if let device {
            if let device = devices.first(where: { $0.name == device }) {
                try await runApp(
                    on: .physical(device),
                    preview: preview,
                    previewLink: previewLink
                )
            } else if let simulator = simulators.first(where: { $0.device.name == device }) {
                try await runApp(
                    on: .simulator(simulator),
                    preview: preview,
                    previewLink: previewLink
                )
            } else {
                throw RunCommandServiceError.deviceNotFound(device)
            }

            return
        }

        let bootedSimulators = simulators.filter { !$0.device.isShutdown }
        if bootedSimulators.count == 1, let bootedDevice = bootedSimulators.first {
            try await runApp(
                on: .simulator(bootedDevice),
                preview: preview,
                previewLink: previewLink
            )
        } else {
            let destinationDevices: [DestinationDevice] = devices.map(DestinationDevice.physical) + simulators
                .map(DestinationDevice.simulator)
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

    private func simulators(
        for preview: ServerPreview
    ) async throws -> [SimulatorDeviceAndRuntime] {
        try await simulatorController.devicesAndRuntimes().filter { deviceAndRuntime in
            try preview.supportedPlatforms.contains { supportedPlatform in
                switch supportedPlatform {
                case .device:
                    return false
                case let .simulator(platform):
                    return try deviceAndRuntime.runtime.platform() == platform
                }
            }
        }
        .sorted(by: {
            if $0.device.isShutdown != $1.device.isShutdown {
                if $0.device.isShutdown {
                    return false
                } else {
                    return true
                }
            } else {
                return $0.device.description < $1.device.description
            }
        })
    }

    private func appBundle(
        for destination: DestinationType,
        preview: ServerPreview,
        previewLink: URL
    ) async throws -> AppBundle {
        guard let url = preview.appBuilds.first(where: { $0.supportedPlatforms.contains(destination) })?.url else {
            throw RunCommandServiceError.noCompatibleAppBuild(destination: destination.description)
        }
        let archivePath = try await Noora.current.progressStep(message: "Downloading preview...") { _ in
            return try await remoteArtifactDownloader.download(url: url)
        }
        guard let archivePath else { throw RunCommandServiceError.appNotFound(previewLink.absoluteString) }

        let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()

        try await fileSystem.remove(archivePath)

        guard let appBundlePath = try await
            fileSystem.glob(directory: unarchivedDirectory, include: ["*.app", "Payload/*.app"])
            .collect()
            .first
        else { throw RunCommandServiceError.appBundleNotFoundInArchive }
        let appBundle = try await appBundleLoader.load(appBundlePath)
        return appBundle
    }

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
            throw RunCommandServiceError.schemeNotFound(scheme: scheme, existing: runnableSchemes.map(\.name))
        }

        guard let graphTarget = graphTraverser.schemeRunnableTarget(scheme: scheme) else {
            throw RunCommandServiceError.schemeWithoutRunnableTarget(scheme: scheme.name)
        }

        try targetRunner.assertCanRunTarget(graphTarget.target)

        try await targetBuilder.buildTarget(
            graphTarget,
            platform: try graphTarget.target.servicePlatform,
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
            platform: try graphTarget.target.servicePlatform,
            workspacePath: workspacePath,
            schemeName: scheme.name,
            configuration: configuration,
            minVersion: minVersion,
            version: version,
            deviceName: device,
            arguments: arguments
        )
    }

    private func runApp(
        on destinationDevice: DestinationDevice,
        preview: ServerPreview,
        previewLink: URL
    ) async throws {
        let destination: DestinationType
        switch destinationDevice {
        case let .physical(physicalDevice):
            destination = .device(physicalDevice.platform)
        case let .simulator(simulator):
            destination = .simulator(try simulator.runtime.platform())
        }
        let appBundle = try await appBundle(
            for: destination,
            preview: preview,
            previewLink: previewLink
        )
        switch destinationDevice {
        case let .physical(physicalDevice):
            try await runApp(
                on: physicalDevice,
                appBundle: appBundle
            )
        case let .simulator(simulatorDevice):
            try await runApp(
                on: simulatorDevice.device,
                appBundle: appBundle
            )
        }
    }

    private func runApp(
        on physicalDevice: PhysicalDevice,
        appBundle: AppBundle
    ) async throws {
        try await Noora.current.progressStep(
            message: "Installing \(appBundle.infoPlist.name) on \(physicalDevice.name)",
            successMessage: "\(appBundle.infoPlist.name) was successfully launched 📲",
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
            successMessage: "\(appBundle.infoPlist.name) was successfully launched 📲",
            errorMessage: nil,
            showSpinner: true
        ) { updateProgress in
            let device = try simulatorController.booted(device: simulatorDevice)
            try simulatorController.installApp(at: appBundle.path, device: device)
            updateProgress("Launching \(appBundle.infoPlist.name) on \(simulatorDevice.name)")
            try await simulatorController.launchApp(bundleId: appBundle.infoPlist.bundleId, device: device, arguments: [])
        }
    }
}

enum DestinationDevice: Equatable {
    case simulator(SimulatorDeviceAndRuntime)
    case physical(PhysicalDevice)
}

extension DestinationDevice: CustomStringConvertible {
    var description: String {
        switch self {
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
        }
    }
}
