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
    case appNotFound(String)
    case fullHandleNotFound

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
        case let .appNotFound(url):
            return "The app at \(url) was not found."
        case .fullHandleNotFound:
            return "You are missing `fullHandle` in your `Config.swift`."
        }
    }

    var type: ErrorType {
        switch self {
        case .schemeNotFound,
             .schemeWithoutRunnableTarget,
             .invalidVersion,
             .appNotFound,
             .fullHandleNotFound:
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
    private let downloadAppBuildService: DownloadAppBuildServicing
    private let serverURLService: ServerURLServicing
    private let fileHandler: FileHandling
    private let appRunner: AppRunning
    private let remoteArtifactDownloader: RemoteArtifactDownloading
    private let appBundleService: AppBundleServicing
    private let fileArchiverFactory: FileArchivingFactorying

    convenience init() {
        self.init(
            generatorFactory: GeneratorFactory(),
            buildGraphInspector: BuildGraphInspector(),
            targetBuilder: TargetBuilder(),
            targetRunner: TargetRunner(),
            configLoader: ConfigLoader(manifestLoader: ManifestLoader()),
            downloadAppBuildService: DownloadAppBuildService(),
            serverURLService: ServerURLService(),
            fileHandler: FileHandler.shared,
            appRunner: AppRunner(),
            remoteArtifactDownloader: RemoteArtifactDownloader(),
            appBundleService: AppBundleService(),
            fileArchiverFactory: FileArchivingFactory()
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        buildGraphInspector: BuildGraphInspecting,
        targetBuilder: TargetBuilding,
        targetRunner: TargetRunning,
        configLoader: ConfigLoading,
        downloadAppBuildService: DownloadAppBuildServicing,
        serverURLService: ServerURLServicing,
        fileHandler: FileHandling,
        appRunner: AppRunning,
        remoteArtifactDownloader: RemoteArtifactDownloading,
        appBundleService: AppBundleServicing,
        fileArchiverFactory: FileArchivingFactorying
    ) {
        self.generatorFactory = generatorFactory
        self.buildGraphInspector = buildGraphInspector
        self.targetBuilder = targetBuilder
        self.targetRunner = targetRunner
        self.configLoader = configLoader
        self.downloadAppBuildService = downloadAppBuildService
        self.serverURLService = serverURLService
        self.fileHandler = fileHandler
        self.appRunner = appRunner
        self.remoteArtifactDownloader = remoteArtifactDownloader
        self.appBundleService = appBundleService
        self.fileArchiverFactory = fileArchiverFactory
    }

    // swiftlint:disable:next function_body_length
    func run(
        path: String?,
        schemeOrShareLink: String,
        generate: Bool,
        clean: Bool,
        configuration: String?,
        device: String?,
        version: String?,
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

        let version = try version.map { versionString in
            guard let version = versionString.version() else {
                throw RunServiceError.invalidVersion(versionString)
            }
            return version
        }

        if schemeOrShareLink.starts(with: "http://") || schemeOrShareLink.starts(with: "https://"),
           let shareLink = URL(string: schemeOrShareLink)
        {
            try await runShareLink(
                shareLink,
                device: device,
                version: version,
                path: runPath
            )
        } else {
            try await runScheme(
                schemeOrShareLink,
                path: runPath,
                generate: generate,
                clean: clean,
                configuration: configuration,
                device: device,
                version: version,
                rosetta: rosetta,
                arguments: arguments
            )
        }
    }

    private func runShareLink(
        _ shareLink: URL,
        device: String?,
        version: Version?,
        path: AbsolutePath
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)
        guard let fullHandle = config.fullHandle else { throw RunServiceError.fullHandleNotFound }

        let serverURL = try serverURLService.url(configServerURL: config.url)

        let downloadURLString = try await downloadAppBuildService.downloadAppBuild(
            shareLink.lastPathComponent,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        guard let downloadURL = URL(string: downloadURLString)
        else { throw RunServiceError.invalidDownloadBuildURL(downloadURLString) }

        guard let archivePath = try await remoteArtifactDownloader.download(url: downloadURL)
        else { throw RunServiceError.appNotFound(shareLink.absoluteString) }

        let unarchivedDirectory = try fileArchiverFactory.makeFileUnarchiver(for: archivePath).unzip()

        let apps = try fileHandler.glob(unarchivedDirectory, glob: "*.app")
            .map(appBundleService.read)

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
