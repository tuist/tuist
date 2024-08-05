import FileSystem
import Foundation
import Path
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
    case invalidDownloadBuildURL(String)
    case invalidPreviewURL(String)
    case appNotFound(String)

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
        case let .invalidDownloadBuildURL(downloadBuildURL):
            return "The download build URL \(downloadBuildURL) is invalid."
        case let .invalidPreviewURL(previewURL):
            return "The preview URL \(previewURL) is invalid."
        case let .appNotFound(url):
            return "The app at \(url) was not found."
        }
    }

    var type: ErrorType {
        switch self {
        case .schemeNotFound,
             .schemeWithoutRunnableTarget,
             .invalidVersion,
             .appNotFound,
             .invalidPreviewURL:
            return .abort
        case .workspaceNotFound, .invalidDownloadBuildURL:
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
    private let downloadPreviewService: DownloadPreviewServicing
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
            downloadPreviewService: DownloadPreviewService(),
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
        downloadPreviewService: DownloadPreviewServicing,
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
        self.downloadPreviewService = downloadPreviewService
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
                version: osVersion,
                path: runPath
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
        }
    }

    private func runPreviewLink(
        _ previewLink: URL,
        device: String?,
        version: Version?,
        path _: AbsolutePath
    ) async throws {
        guard let scheme = previewLink.scheme,
              let host = previewLink.host,
              let serverURL = URL(string: "\(scheme)://\(host)\(previewLink.port.map { ":" + String($0) } ?? "")"),
              previewLink.pathComponents.count > 4 // We expect at least four path components
        else { throw RunServiceError.invalidPreviewURL(previewLink.absoluteString) }

        let downloadURLString = try await downloadPreviewService.downloadPreview(
            previewLink.lastPathComponent,
            fullHandle: "\(previewLink.pathComponents[1])/\(previewLink.pathComponents[2])",
            serverURL: serverURL
        )

        guard let downloadURL = URL(string: downloadURLString)
        else { throw RunServiceError.invalidDownloadBuildURL(downloadURLString) }

        guard let archivePath = try await remoteArtifactDownloader.download(url: downloadURL)
        else { throw RunServiceError.appNotFound(previewLink.absoluteString) }

        let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()

        try await fileSystem.remove(archivePath)

        let apps = try await fileHandler.glob(unarchivedDirectory, glob: "*.app")
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
        let generator = generatorFactory.defaultGenerator(config: config)
        if try (generate || buildGraphInspector.workspacePath(directory: path) == nil) {
            logger.notice("Generating project for running", metadata: .section)
            graph = try await generator.generateWithGraph(path: path).1
        } else {
            graph = try await generator.load(path: path)
        }

        guard let workspacePath = try buildGraphInspector.workspacePath(directory: path) else {
            throw RunServiceError.workspaceNotFound(path: path.pathString)
        }

        let graphTraverser = GraphTraverser(graph: graph)
        let runnableSchemes = buildGraphInspector.runnableSchemes(graphTraverser: graphTraverser)

        logger.debug("Found the following runnable schemes: \(runnableSchemes.map(\.name).joined(separator: ", "))")

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
