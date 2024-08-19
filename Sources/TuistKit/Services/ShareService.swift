import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph

enum ShareServiceError: Equatable, FatalError {
    case projectOrWorkspaceNotFound(path: String)
    case noAppsFound(app: String, configuration: String)
    case appNotSpecified
    case multipleAppsSpecified([String])
    case platformsNotSpecified
    case fullHandleNotFound

    var description: String {
        switch self {
        case let .projectOrWorkspaceNotFound(path):
            return "Workspace or project not found at \(path)"
        case let .noAppsFound(app: app, configuration: configuration):
            return "\(app) for the \(configuration) configuration was not found. You can build it by running `tuist build \(app)`"
        case .appNotSpecified:
            return "If you're not using Tuist projects, you must specify the app name when sharing an app, such as `tuist share App --platforms ios`."
        case .platformsNotSpecified:
            return "If you're not using Tuist projects, you must specify the platforms when sharing an app, such as `tuist share App --platforms ios`."
        case let .multipleAppsSpecified(apps):
            return "You specified multiple apps to share: \(apps.joined(separator: " ")). You cannot specify multiple apps when using `tuist share`."
        case .fullHandleNotFound:
            return "You are missing full handle in your Config.swift."
        }
    }

    var type: ErrorType {
        switch self {
        case .projectOrWorkspaceNotFound, .noAppsFound, .appNotSpecified, .platformsNotSpecified, .multipleAppsSpecified,
             .fullHandleNotFound:
            return .abort
        }
    }
}

struct ShareService {
    private let fileHandler: FileHandling
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let buildGraphInspector: BuildGraphInspecting
    private let previewsUploadService: PreviewsUploadServicing
    private let configLoader: ConfigLoading
    private let serverURLService: ServerURLServicing
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private let userInputReader: UserInputReading
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let appBundleLoader: AppBundleLoading

    init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )

        self.init(
            fileHandler: FileHandler.shared,
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
            buildGraphInspector: BuildGraphInspector(),
            previewsUploadService: PreviewsUploadService(),
            configLoader: ConfigLoader(),
            serverURLService: ServerURLService(),
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            userInputReader: UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            appBundleLoader: AppBundleLoader()
        )
    }

    init(
        fileHandler: FileHandling,
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
        buildGraphInspector: BuildGraphInspecting,
        previewsUploadService: PreviewsUploadServicing,
        configLoader: ConfigLoading,
        serverURLService: ServerURLServicing,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading,
        userInputReader: UserInputReading,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        appBundleLoader: AppBundleLoading
    ) {
        self.fileHandler = fileHandler
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.buildGraphInspector = buildGraphInspector
        self.previewsUploadService = previewsUploadService
        self.configLoader = configLoader
        self.serverURLService = serverURLService
        self.manifestLoader = manifestLoader
        self.manifestGraphLoader = manifestGraphLoader
        self.userInputReader = userInputReader
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.appBundleLoader = appBundleLoader
    }

    func run(
        path: String?,
        apps: [String],
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?
    ) async throws {
        let path = try self.path(path)

        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else { throw ShareServiceError.fullHandleNotFound }

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: fileHandler.currentPath
            )
        }

        if !apps.isEmpty, apps.allSatisfy({ $0.hasSuffix(".app") }) {
            let appPaths = try apps.map {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: fileHandler.currentPath
                )
            }

            let appBundles = try await appPaths.concurrentMap {
                try await appBundleLoader.load($0)
            }

            let appNames = appBundles.map(\.infoPlist.name).uniqued()
            guard appNames.count == 1,
                  let appName = appNames.first else { throw ShareServiceError.multipleAppsSpecified(appNames) }

            let url = try await previewsUploadService.uploadPreviews(
                appPaths,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            logger.notice("\(appName) uploaded – share it with others using the following link: \(url.absoluteString)")
        } else if manifestLoader.hasRootManifest(at: path) {
            guard apps.count < 2 else { throw ShareServiceError.multipleAppsSpecified(apps) }

            let (graph, _, _, _) = try await manifestGraphLoader.load(path: path)
            let graphTraverser = GraphTraverser(graph: graph)
            let appTargets = graphTraverser.targets(product: .app)
                .map { $0 }
                .filter {
                    if let app = apps.first {
                        return $0.target.name == app
                    } else {
                        return true
                    }
                }
            let appTarget: GraphTarget = try userInputReader.readValue(
                asking: "Select the app that you want to share:",
                values: appTargets.sorted(by: { $0.target.name < $1.target.name }),
                valueDescription: \.target.name
            )

            let configuration = try defaultConfigurationFetcher.fetch(
                configuration: configuration,
                config: config,
                graph: graph
            )

            let platforms = platforms.isEmpty ? appTarget.target.supportedPlatforms.map { $0 } : platforms

            try await uploadPreviews(
                for: platforms,
                workspacePath: graph.workspace.xcWorkspacePath,
                configuration: configuration,
                app: appTarget.target.productName,
                derivedDataPath: derivedDataPath,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        } else {
            guard !apps.isEmpty else { throw ShareServiceError.appNotSpecified }
            guard apps.count == 1, let app = apps.first else { throw ShareServiceError.multipleAppsSpecified(apps) }
            guard !platforms.isEmpty else { throw ShareServiceError.platformsNotSpecified }

            let configuration = configuration ?? BuildConfiguration.debug.name

            guard let workspaceOrProjectPath = fileHandler.glob(path, glob: "*.xcworkspace").first ?? fileHandler
                .glob(path, glob: "*.xcodeproj").first
            else {
                throw ShareServiceError.projectOrWorkspaceNotFound(path: path.pathString)
            }

            try await uploadPreviews(
                for: platforms,
                workspacePath: workspaceOrProjectPath,
                configuration: configuration,
                app: app,
                derivedDataPath: derivedDataPath,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func uploadPreviews(
        for platforms: [Platform],
        workspacePath: AbsolutePath,
        configuration: String,
        app: String,
        derivedDataPath: AbsolutePath?,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        try await fileHandler.inTemporaryDirectory { temporaryPath in
            let appPaths = try platforms
                .map { platform in
                    let sdkPathComponent: String = {
                        guard platform != .macOS else {
                            return platform.xcodeDeviceSDK
                        }
                        return "\(platform.xcodeSimulatorSDK!)"
                    }()

                    let appPath = try xcodeProjectBuildDirectoryLocator.locate(
                        platform: platform,
                        projectPath: workspacePath,
                        derivedDataPath: derivedDataPath,
                        configuration: configuration
                    )
                    .appending(component: "\(app).app")

                    let newAppPath = temporaryPath.appending(component: "\(sdkPathComponent)-\(app).app")

                    if !fileHandler.exists(appPath) {
                        throw ShareServiceError.noAppsFound(app: app, configuration: configuration)
                    }

                    try fileHandler.copy(from: appPath, to: newAppPath)

                    return newAppPath
                }
                .uniqued()

            let url = try await previewsUploadService.uploadPreviews(
                appPaths,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            logger.notice("\(app) uploaded – share it with others using the following link: \(url.absoluteString)")
        }
    }
}
