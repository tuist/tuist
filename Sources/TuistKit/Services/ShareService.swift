import FileSystem
import Foundation
import Path
import ServiceContextModule
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
    case appBundleInIPANotFound(AbsolutePath)

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
            return "You are missing full handle in your \(Constants.tuistManifestFileName)"
        case let .appBundleInIPANotFound(ipaPath):
            return "No app found in the in the .ipa archive at \(ipaPath). Make sure the .ipa is a valid application archive."
        }
    }

    var type: ErrorType {
        switch self {
        case .projectOrWorkspaceNotFound, .noAppsFound, .appNotSpecified, .platformsNotSpecified, .multipleAppsSpecified,
             .fullHandleNotFound, .appBundleInIPANotFound:
            return .abort
        }
    }
}

// swiftlint:disable:next type_body_length
struct ShareService {
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming
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
    private let fileArchiverFactory: FileArchivingFactorying

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
            fileSystem: FileSystem(),
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
            buildGraphInspector: BuildGraphInspector(),
            previewsUploadService: PreviewsUploadService(),
            configLoader: ConfigLoader(),
            serverURLService: ServerURLService(),
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            userInputReader: UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            appBundleLoader: AppBundleLoader(),
            fileArchiverFactory: FileArchivingFactory()
        )
    }

    init(
        fileHandler: FileHandling,
        fileSystem: FileSysteming,
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
        buildGraphInspector: BuildGraphInspecting,
        previewsUploadService: PreviewsUploadServicing,
        configLoader: ConfigLoading,
        serverURLService: ServerURLServicing,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading,
        userInputReader: UserInputReading,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        appBundleLoader: AppBundleLoading,
        fileArchiverFactory: FileArchivingFactorying
    ) {
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
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
        self.fileArchiverFactory = fileArchiverFactory
    }

    func run(
        path: String?,
        apps: [String],
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?,
        json: Bool
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

        let appPaths = try await apps.concurrentMap {
            try AbsolutePath(
                validating: $0,
                relativeTo: path
            )
        }
        if appPaths.contains(where: { $0.extension == "ipa" }) {
            try await shareIPA(
                appPaths,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json
            )
        } else if appPaths.contains(where: { $0.extension == "app" }) {
            try await shareAppBundles(
                appPaths,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json
            )
        } else if try await manifestLoader.hasRootManifest(at: path) {
            guard apps.count < 2 else { throw ShareServiceError.multipleAppsSpecified(apps) }

            let (graph, _, _, _) = try await manifestGraphLoader.load(path: path)
            let graphTraverser = GraphTraverser(graph: graph)
            let shareableTargets = graphTraverser
                .targets(product: .app)
                .union(graphTraverser.targets(product: .appClip))
                .union(graphTraverser.targets(product: .watch2App))
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
                values: shareableTargets.sorted(by: { $0.target.name < $1.target.name }),
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
                serverURL: serverURL,
                json: json
            )
        } else {
            guard !apps.isEmpty else { throw ShareServiceError.appNotSpecified }
            guard apps.count == 1, let app = apps.first else { throw ShareServiceError.multipleAppsSpecified(apps) }
            guard !platforms.isEmpty else { throw ShareServiceError.platformsNotSpecified }

            let configuration = configuration ?? BuildConfiguration.debug.name

            let workspace = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"]).collect().first
            let project = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"]).collect().first
            guard let workspaceOrProjectPath = workspace ?? project
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
                serverURL: serverURL,
                json: json
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

    private func shareIPA(
        _ appPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL,
        json: Bool
    ) async throws {
        guard appPaths.count == 1,
              let ipaPath = appPaths.first else { throw ShareServiceError.multipleAppsSpecified(appPaths.map(\.pathString)) }

        guard let appBundlePath = try await fileSystem.glob(
            directory: fileArchiverFactory.makeFileUnarchiver(for: ipaPath).unzip(),
            include: ["**/*.app"]
        )
        .collect()
        .first
        else { throw ShareServiceError.appBundleInIPANotFound(ipaPath) }
        let appBundle = try await appBundleLoader.load(appBundlePath)
        let displayName = appBundle.infoPlist.name

        try await uploadPreviews(
            .ipa(ipaPath),
            displayName: displayName,
            version: appBundle.infoPlist.version.description,
            bundleIdentifier: appBundle.infoPlist.bundleId,
            icon: iconPaths(for: appBundle).first,
            supportedPlatforms: appBundle.infoPlist.supportedPlatforms,
            fullHandle: fullHandle,
            serverURL: serverURL,
            json: json
        )
    }

    private func shareAppBundles(
        _ appPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL,
        json: Bool
    ) async throws {
        let appBundles = try await appPaths.concurrentMap {
            try await appBundleLoader.load($0)
        }

        let appNames = appBundles.map(\.infoPlist.name).uniqued()
        guard appNames.count == 1,
              let appName = appNames.first,
              appPaths.allSatisfy({ $0.extension == "app" })
        else { throw ShareServiceError.multipleAppsSpecified(appNames) }

        try await uploadPreviews(
            .appBundles(appPaths),
            displayName: appName,
            version: appBundles.map(\.infoPlist.version.description).first,
            bundleIdentifier: appBundles.map(\.infoPlist.bundleId).first,
            icon: appBundles
                .concurrentFlatMap { try await iconPaths(for: $0) }
                .first,
            supportedPlatforms: appBundles.flatMap(\.infoPlist.supportedPlatforms),
            fullHandle: fullHandle,
            serverURL: serverURL,
            json: json
        )
    }

    private func copyAppBundle(
        for destinationType: DestinationType,
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        temporaryPath: AbsolutePath
    ) async throws -> AbsolutePath? {
        let appPath = try xcodeProjectBuildDirectoryLocator.locate(
            destinationType: destinationType,
            projectPath: projectPath,
            derivedDataPath: derivedDataPath,
            configuration: configuration
        )
        .appending(component: "\(app).app")

        let newAppPath = temporaryPath.appending(
            component: "\(destinationType.buildProductDestinationPathComponent(for: configuration))-\(app).app"
        )

        if try await !fileSystem.exists(appPath) {
            return nil
        }

        try await fileSystem.copy(appPath, to: newAppPath)

        return newAppPath
    }

    private func uploadPreviews(
        for platforms: [Platform],
        workspacePath: AbsolutePath,
        configuration: String,
        app: String,
        derivedDataPath: AbsolutePath?,
        fullHandle: String,
        serverURL: URL,
        json: Bool
    ) async throws {
        try await fileHandler.inTemporaryDirectory { temporaryPath in
            let appPaths = try await platforms
                .concurrentFlatMap { platform -> [DestinationType] in
                    switch platform {
                    case .iOS, .tvOS, .visionOS, .watchOS:
                        return [
                            .simulator(platform),
                            .device(platform),
                        ]
                    case .macOS:
                        return [.device(platform)]
                    }
                }
                .concurrentCompactMap { destinationType in
                    try await copyAppBundle(
                        for: destinationType,
                        app: app,
                        projectPath: workspacePath,
                        derivedDataPath: derivedDataPath,
                        configuration: configuration,
                        temporaryPath: temporaryPath
                    )
                }
                .uniqued()

            let appBundles = try await appPaths.concurrentMap {
                try await appBundleLoader.load($0)
            }

            if appPaths.isEmpty {
                throw ShareServiceError.noAppsFound(app: app, configuration: configuration)
            }

            try await uploadPreviews(
                .appBundles(appPaths),
                displayName: app,
                version: appBundles.first?.infoPlist.version.description,
                bundleIdentifier: appBundles.first?.infoPlist.bundleId,
                icon: appBundles
                    .concurrentFlatMap { try await iconPaths(for: $0) }
                    .first,
                supportedPlatforms: appBundles.flatMap(\.infoPlist.supportedPlatforms),
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json
            )
        }
    }

    private func iconPaths(for appBundle: AppBundle) async throws -> [AbsolutePath] {
        try await appBundle.infoPlist.bundleIcons?.primaryIcon?.iconFiles
            // This is a convention for iOS icons. We might need to adjust this for other platforms in the future.
            .map { appBundle.path.appending(component: $0 + "@2x.png") }
            .concurrentFilter {
                try await fileSystem.exists($0)
            } ?? []
    }

    private func uploadPreviews(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        version: String?,
        bundleIdentifier: String?,
        icon: AbsolutePath?,
        supportedPlatforms: [DestinationType],
        fullHandle: String,
        serverURL: URL,
        json: Bool
    ) async throws {
        ServiceContext.current?.logger?.notice("Uploading \(displayName)...")
        let preview = try await previewsUploadService.uploadPreviews(
            previewUploadType,
            displayName: displayName,
            version: version,
            bundleIdentifier: bundleIdentifier,
            icon: icon,
            supportedPlatforms: supportedPlatforms,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
        ServiceContext.current?.logger?
            .notice("\(displayName) uploaded – share it with others using the following link: \(preview.url.absoluteString)")

        await ServiceContext.current?.runMetadataStorage?.update(previewId: preview.id)

        if json {
            let previewJSON = try preview.toJSON()
            ServiceContext.current?.logger?.info(
                .init(
                    stringLiteral: previewJSON.toString(prettyPrint: true)
                ),
                metadata: .json
            )
        }
    }
}
