import FileSystem
import Foundation
import Path
import ServiceContextModule
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

enum RunServiceError: FatalError, Equatable {
    case schemeNotFound(scheme: String, existing: [String])
    case schemeWithoutRunnableTarget(scheme: String)
    case invalidVersion(String)
    case workspaceNotFound(path: String)
    case invalidPreviewURL(String)
    case appNotFound(String)
    case missingFullHandle(displayName: String, specifier: String)
    case previewNotFound(displayName: String, specifier: String)

    var description: String {
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
        }
    }

    var type: ErrorType {
        switch self {
        case .schemeNotFound,
             .schemeWithoutRunnableTarget,
             .invalidVersion,
             .appNotFound,
             .invalidPreviewURL,
             .missingFullHandle,
             .previewNotFound:
            return .abort
        case .workspaceNotFound:
            return .bug
        }
    }
}

final class RunService {
    private let generatorFactory: GeneratorFactorying
    private let buildGraphInspector: BuildGraphInspecting
    private let targetBuilder: TargetBuilding
    private let targetRunner: TargetRunning
    private let configLoader: ConfigLoading
    private let getPreviewService: GetPreviewServicing
    private let listPreviewsService: ListPreviewsServicing
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming
    private let appRunner: AppRunning
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let appBundleLoader: AppBundleLoading
    private let fileArchiverFactory: FileArchivingFactorying

    convenience init() {
        self.init(
            generatorFactory: GeneratorFactory(),
            buildGraphInspector: BuildGraphInspector(),
            targetBuilder: TargetBuilder(),
            targetRunner: TargetRunner(),
            configLoader: ConfigLoader(manifestLoader: ManifestLoader()),
            getPreviewService: GetPreviewService(),
            listPreviewsService: ListPreviewsService(),
            fileHandler: FileHandler.shared,
            fileSystem: FileSystem(),
            appRunner: AppRunner(),
            remoteArtifactDownloader: RemoteArtifactDownloader(),
            appBundleLoader: AppBundleLoader(),
            fileArchiverFactory: FileArchivingFactory()
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
        fileHandler: FileHandling,
        fileSystem: FileSystem,
        appRunner: AppRunning,
        remoteArtifactDownloader: RemoteArtifactDownloading,
        appBundleLoader: AppBundleLoading,
        fileArchiverFactory: FileArchivingFactorying
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.targetRunner = targetRunner
        self.configLoader = configLoader
        self.getPreviewService = getPreviewService
        self.listPreviewsService = listPreviewsService
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
        self.appRunner = appRunner
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.appBundleLoader = appBundleLoader
        self.fileArchiverFactory = fileArchiverFactory
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
                throw RunServiceError.invalidVersion(versionString)
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
                throw RunServiceError.missingFullHandle(
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
            ).first else { throw RunServiceError.previewNotFound(displayName: displayName, specifier: specifier) }
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
        version: Version?
    ) async throws {
        ServiceContext.current?.logger?.notice("Runnning \(previewLink.absoluteString)...")
        guard let scheme = previewLink.scheme,
              let host = previewLink.host,
              let serverURL = URL(string: "\(scheme)://\(host)\(previewLink.port.map { ":" + String($0) } ?? "")"),
              previewLink.pathComponents.count > 4 // We expect at least four path components
        else { throw RunServiceError.invalidPreviewURL(previewLink.absoluteString) }

        let preview = try await getPreviewService.getPreview(
            previewLink.lastPathComponent,
            fullHandle: "\(previewLink.pathComponents[1])/\(previewLink.pathComponents[2])",
            serverURL: serverURL
        )

        guard let archivePath = try await remoteArtifactDownloader.download(url: preview.url)
        else { throw RunServiceError.appNotFound(previewLink.absoluteString) }

        let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()

        try await fileSystem.remove(archivePath)

        let apps = try await
            fileSystem.glob(directory: unarchivedDirectory, include: ["*.app", "Payload/*.app"])
            .collect()
            .concurrentMap {
                try await self.appBundleLoader.load($0)
            }

        try await appRunner.runApp(
            apps,
            version: version,
            device: device
        )
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
        let generator = generatorFactory.defaultGenerator(config: config, sources: [])
        let workspacePath = try await buildGraphInspector.workspacePath(directory: path)
        if generate || workspacePath == nil {
            ServiceContext.current?.logger?.notice("Generating project for running", metadata: .section)
            graph = try await generator.generateWithGraph(path: path).1
        } else {
            graph = try await generator.load(path: path)
        }

        guard let workspacePath = try await buildGraphInspector.workspacePath(directory: path) else {
            throw RunServiceError.workspaceNotFound(path: path.pathString)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let runnableSchemes = buildGraphInspector.runnableSchemes(graphTraverser: graphTraverser)

        ServiceContext.current?.logger?
            .debug("Found the following runnable schemes: \(runnableSchemes.map(\.name).joined(separator: ", "))")

        guard let scheme = runnableSchemes.first(where: { $0.name == scheme }) else {
            throw RunServiceError.schemeNotFound(scheme: scheme, existing: runnableSchemes.map(\.name))
        }

        guard let graphTarget = buildGraphInspector.runnableTarget(scheme: scheme, graphTraverser: graphTraverser) else {
            throw RunServiceError.schemeWithoutRunnableTarget(scheme: scheme.name)
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
}
