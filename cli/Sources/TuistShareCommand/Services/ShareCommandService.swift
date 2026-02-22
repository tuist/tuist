import FileSystem
import Foundation
import Noora
import Path
import TuistAlert
import TuistAndroid
import TuistConfigLoader
import TuistConstants
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistServer
import TuistSupport

#if os(macOS)
    import TuistAutomation
    import TuistCore
    import TuistKit
    import TuistLoader
    import TuistSimulator
    import TuistUserInputReader
    import XcodeGraph
#endif

enum ShareCommandServiceError: Equatable, LocalizedError {
    case fullHandleNotFound
    case multipleAppsSpecified([String])
    #if os(macOS)
        case projectOrWorkspaceNotFound(path: String)
        case noAppsFound(app: String, configuration: String)
        case appNotSpecified
        case platformsNotSpecified
    #endif
    case appleBuildsSharingNotSupportedOnLinux

    var errorDescription: String? {
        switch self {
        case .fullHandleNotFound:
            return "You are missing fullHandle in your \(Constants.tuistManifestFileName). Run 'tuist init' to get started with remote Tuist features."
        case let .multipleAppsSpecified(apps):
            return "You specified multiple apps to share: \(apps.joined(separator: " ")). You cannot specify multiple apps when using `tuist share`."
        #if os(macOS)
            case let .projectOrWorkspaceNotFound(path):
                return "Workspace or project not found at \(path)"
            case let .noAppsFound(app: app, configuration: configuration):
                return "\(app) for the \(configuration) configuration was not found. You can build it by running `tuist build \(app)`"
            case .appNotSpecified:
                return "If you're not using Tuist projects, you must specify the app name when sharing an app, such as `tuist share App --platforms ios`."
            case .platformsNotSpecified:
                return "If you're not using Tuist projects, you must specify the platforms when sharing an app, such as `tuist share App --platforms ios`."
        #endif
        case .appleBuildsSharingNotSupportedOnLinux:
            return "Sharing Apple app bundles and IPAs is only supported on macOS. On Linux, only APK files can be shared."
        }
    }
}

// swiftlint:disable:next type_body_length
struct ShareCommandService {
    private let fileSystem: FileSysteming
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let previewsUploadService: PreviewsUploadServicing
    private let apkMetadataService: APKMetadataServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let gitController: GitControlling

    #if os(macOS)
        private let fileHandler: FileHandling
        private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
        private let buildGraphInspector: BuildGraphInspecting
        private let manifestLoader: ManifestLoading
        private let manifestGraphLoader: ManifestGraphLoading
        private let userInputReader: UserInputReading
        private let defaultConfigurationFetcher: DefaultConfigurationFetching
        private let appBundleLoader: AppBundleLoading
    #endif

    init() {
        #if os(macOS)
            let manifestLoader = ManifestLoader.current
            let manifestGraphLoader = ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: []),
                graphMapper: SequentialGraphMapper([])
            )

            self.init(
                fileSystem: FileSystem(),
                configLoader: ConfigLoader(),
                serverEnvironmentService: ServerEnvironmentService(),
                previewsUploadService: PreviewsUploadService(),
                apkMetadataService: APKMetadataService(),
                fileArchiverFactory: FileArchivingFactory(),
                gitController: GitController(),
                fileHandler: FileHandler.shared,
                xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
                buildGraphInspector: BuildGraphInspector(),
                manifestLoader: manifestLoader,
                manifestGraphLoader: manifestGraphLoader,
                userInputReader: UserInputReader(),
                defaultConfigurationFetcher: DefaultConfigurationFetcher(),
                appBundleLoader: AppBundleLoader()
            )
        #else
            self.init(
                fileSystem: FileSystem(),
                configLoader: ConfigLoader(),
                serverEnvironmentService: ServerEnvironmentService(),
                previewsUploadService: PreviewsUploadService(),
                apkMetadataService: APKMetadataService(),
                fileArchiverFactory: FileArchivingFactory(),
                gitController: GitController()
            )
        #endif
    }

    #if os(macOS)
        init(
            fileSystem: FileSysteming,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            previewsUploadService: PreviewsUploadServicing,
            apkMetadataService: APKMetadataServicing,
            fileArchiverFactory: FileArchivingFactorying,
            gitController: GitControlling,
            fileHandler: FileHandling,
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
            buildGraphInspector: BuildGraphInspecting,
            manifestLoader: ManifestLoading,
            manifestGraphLoader: ManifestGraphLoading,
            userInputReader: UserInputReading,
            defaultConfigurationFetcher: DefaultConfigurationFetching,
            appBundleLoader: AppBundleLoading
        ) {
            self.fileSystem = fileSystem
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.previewsUploadService = previewsUploadService
            self.apkMetadataService = apkMetadataService
            self.fileArchiverFactory = fileArchiverFactory
            self.gitController = gitController
            self.fileHandler = fileHandler
            self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
            self.buildGraphInspector = buildGraphInspector
            self.manifestLoader = manifestLoader
            self.manifestGraphLoader = manifestGraphLoader
            self.userInputReader = userInputReader
            self.defaultConfigurationFetcher = defaultConfigurationFetcher
            self.appBundleLoader = appBundleLoader
        }
    #else
        init(
            fileSystem: FileSysteming,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            previewsUploadService: PreviewsUploadServicing,
            apkMetadataService: APKMetadataServicing,
            fileArchiverFactory: FileArchivingFactorying,
            gitController: GitControlling
        ) {
            self.fileSystem = fileSystem
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.previewsUploadService = previewsUploadService
            self.apkMetadataService = apkMetadataService
            self.fileArchiverFactory = fileArchiverFactory
            self.gitController = gitController
        }
    #endif

    // MARK: - macOS run

    #if os(macOS)
        // swiftlint:disable:next function_body_length
        func run(
            path: String?,
            apps: [String],
            configuration: String?,
            platforms: [Platform],
            derivedDataPath: String?,
            json: Bool,
            track: String?
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            guard let fullHandle = config.fullHandle else {
                throw ShareCommandServiceError.fullHandleNotFound
            }

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
            if appPaths.contains(where: { $0.extension == "apk" }) {
                try await shareAPK(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else if appPaths.contains(where: { $0.extension == "ipa" }) {
                try await shareIPA(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else if appPaths.contains(where: { $0.extension == "app" }) {
                try await shareAppBundles(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else if try await manifestLoader.hasRootManifest(at: path) {
                guard apps.count < 2 else { throw ShareCommandServiceError.multipleAppsSpecified(apps) }

                let (graph, _, _, _) = try await manifestGraphLoader.load(
                    path: path,
                    disableSandbox: config.project.disableSandbox
                )
                let graphTraverser = GraphTraverser(graph: graph)
                let shareableTargets =
                    graphTraverser
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
                    defaultConfiguration: config.project.generatedProject?.generationOptions
                        .defaultConfiguration,
                    graph: graph
                )

                let platforms =
                    platforms.isEmpty ? appTarget.target.supportedPlatforms.map { $0 } : platforms

                try await uploadApplePreview(
                    for: platforms,
                    workspacePath: graph.workspace.xcWorkspacePath,
                    configuration: configuration,
                    app: appTarget.target.productName,
                    derivedDataPath: derivedDataPath,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else {
                guard !apps.isEmpty else { throw ShareCommandServiceError.appNotSpecified }
                guard apps.count == 1, let app = apps.first else {
                    throw ShareCommandServiceError.multipleAppsSpecified(apps)
                }
                guard !platforms.isEmpty else { throw ShareCommandServiceError.platformsNotSpecified }

                let configuration = configuration ?? BuildConfiguration.debug.name

                let workspace = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"])
                    .collect().first
                let project = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"])
                    .collect().first
                guard let workspaceOrProjectPath = workspace ?? project
                else {
                    throw ShareCommandServiceError.projectOrWorkspaceNotFound(path: path.pathString)
                }

                try await uploadApplePreview(
                    for: platforms,
                    workspacePath: workspaceOrProjectPath,
                    configuration: configuration,
                    app: app,
                    derivedDataPath: derivedDataPath,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            }
        }
    #endif

    // MARK: - Linux run

    #if !os(macOS)
        func run(
            path: String?,
            apps: [String],
            json: Bool,
            track: String?
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            guard let fullHandle = config.fullHandle else {
                throw ShareCommandServiceError.fullHandleNotFound
            }

            let appPaths = try await apps.concurrentMap {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: path
                )
            }

            guard appPaths.allSatisfy({ $0.extension == "apk" }) else {
                throw ShareCommandServiceError.appleBuildsSharingNotSupportedOnLinux
            }

            try await shareAPK(
                appPaths,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json,
                track: track
            )
        }
    #endif

    // MARK: - Cross-platform APK sharing

    private func shareAPK(
        _ appPaths: [AbsolutePath],
        path: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        json: Bool,
        track: String?
    ) async throws {
        guard appPaths.count == 1,
              let apkPath = appPaths.first
        else { throw ShareCommandServiceError.multipleAppsSpecified(appPaths.map(\.pathString)) }

        let metadata = try await apkMetadataService.parseMetadata(at: apkPath)

        let gitInfo = resolveGitInfo(at: path)

        let preview = try await Noora.current.progressBarStep(
            message: "Uploading \(metadata.displayName)",
            successMessage: "\(metadata.displayName) uploaded",
            errorMessage: "Failed to upload \(metadata.displayName)"
        ) { updateProgress in
            try await previewsUploadService.uploadPreview(
                .apk(path: apkPath, metadata: metadata),
                fullHandle: fullHandle,
                serverURL: serverURL,
                gitBranch: gitInfo.branch,
                gitCommitSHA: gitInfo.sha,
                gitRef: gitInfo.ref,
                track: track,
                updateProgress: updateProgress
            )
        }

        outputResult(preview, displayName: metadata.displayName, json: json)
    }

    private func resolveGitInfo(at path: AbsolutePath) -> GitInfo {
        (try? gitController.gitInfo(workingDirectory: path)) ?? GitInfo(
            ref: nil,
            branch: nil,
            sha: nil,
            remoteURLOrigin: nil
        )
    }

    // MARK: - macOS-only Apple sharing

    #if os(macOS)
        private func shareIPA(
            _ appPaths: [AbsolutePath],
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            guard appPaths.count == 1,
                  let ipaPath = appPaths.first
            else { throw ShareCommandServiceError.multipleAppsSpecified(appPaths.map(\.pathString)) }

            let appBundle = try await appBundleLoader.load(ipa: ipaPath)
            let displayName = appBundle.infoPlist.name

            let preview = try await uploadApplePreviewType(
                .ipa(appBundle),
                displayName: displayName,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                track: track
            )

            outputResult(preview, displayName: displayName, json: json)
        }

        private func shareAppBundles(
            _ appPaths: [AbsolutePath],
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            let appBundles = try await appPaths.concurrentMap {
                try await appBundleLoader.load($0)
            }

            let appNames = appBundles.map(\.infoPlist.name).uniqued()
            guard appNames.count == 1,
                  let appName = appNames.first,
                  appPaths.allSatisfy({ $0.extension == "app" })
            else { throw ShareCommandServiceError.multipleAppsSpecified(appNames) }

            let preview = try await uploadApplePreviewType(
                .appBundles(appBundles),
                displayName: appName,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                track: track
            )

            outputResult(preview, displayName: appName, json: json)
        }

        private func copyAppBundle(
            for destinationType: DestinationType,
            app: String,
            projectPath: AbsolutePath,
            derivedDataPath: AbsolutePath?,
            configuration: String,
            temporaryPath: AbsolutePath
        ) async throws -> AbsolutePath? {
            let appPath = try await xcodeProjectBuildDirectoryLocator.locate(
                destinationType: destinationType,
                projectPath: projectPath,
                derivedDataPath: derivedDataPath,
                configuration: configuration
            )
            .appending(component: "\(app).app")

            let newAppPath = temporaryPath.appending(
                component:
                "\(destinationType.buildProductDestinationPathComponent(for: configuration))-\(app).app"
            )

            if try await !fileSystem.exists(appPath) {
                return nil
            }

            try await fileSystem.copy(appPath, to: newAppPath)

            return newAppPath
        }

        private func uploadApplePreview(
            for platforms: [Platform],
            workspacePath: AbsolutePath,
            configuration: String,
            app: String,
            derivedDataPath: AbsolutePath?,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            try await fileHandler.inTemporaryDirectory { temporaryPath in
                let appPaths =
                    try await platforms
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
                    throw ShareCommandServiceError.noAppsFound(app: app, configuration: configuration)
                }

                let preview = try await uploadApplePreviewType(
                    .appBundles(appBundles),
                    displayName: app,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    track: track
                )

                outputResult(preview, displayName: app, json: json)
            }
        }

        private func uploadApplePreviewType(
            _ previewUploadType: PreviewUploadType,
            displayName: String,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            track: String?
        ) async throws -> Components.Schemas.Preview {
            let gitInfo = resolveGitInfo(at: path)

            return try await Noora.current.progressBarStep(
                message: "Uploading \(displayName)",
                successMessage: "\(displayName) uploaded",
                errorMessage: "Failed to upload \(displayName)"
            ) { updateProgress in
                try await previewsUploadService.uploadPreview(
                    previewUploadType,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    gitBranch: gitInfo.branch,
                    gitCommitSHA: gitInfo.sha,
                    gitRef: gitInfo.ref,
                    track: track,
                    updateProgress: updateProgress
                )
            }
        }
    #endif

    // MARK: - Helpers

    private func outputResult(_ preview: Components.Schemas.Preview, displayName: String, json: Bool) {
        AlertController.current
            .success(
                .alert(
                    "Share \(displayName) with others using the following link: \(preview.url)"
                )
            )

        #if os(macOS)
            Task {
                await RunMetadataStorage.current.update(previewId: preview.id)
            }
        #endif

        if json {
            if let previewJSON = try? preview.toJSON() {
                Logger.current.info(
                    .init(
                        stringLiteral: previewJSON.toString(prettyPrint: true)
                    ),
                    metadata: .json
                )
            }
        }
    }
}
