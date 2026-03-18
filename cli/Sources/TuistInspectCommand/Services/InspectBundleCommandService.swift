import FileSystem
import Foundation
import Noora
import Path
import Rosalind
import TuistAlert
import TuistConfigLoader
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistServer
import TuistSupport

#if os(macOS)
    import TuistCore
    import TuistLoader
    import TuistSimulator
    import TuistUserInputReader
    import XcodeGraph
#endif

public enum InspectBundleCommandServiceError: LocalizedError {
    case missingFullHandle
    #if os(macOS)
        case projectOrWorkspaceNotFound(path: String)
        case noAppsFound(app: String, configuration: String)
        case multipleBuiltBundlesFound(app: String, paths: [String])
        case platformsNotSpecified
    #endif

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            "To analyze the app bundle, run 'tuist init' to connect to the Tuist server."
        #if os(macOS)
            case let .projectOrWorkspaceNotFound(path):
                "Workspace or project not found at \(path)"
            case let .noAppsFound(app, configuration):
                "\(app) for the \(configuration) configuration was not found. You can build it by running `xcodebuild build -scheme \(app) -configuration \(configuration)`"
            case let .multipleBuiltBundlesFound(app, paths):
                "Multiple built bundles were found for \(app): \(paths.joined(separator: ", ")). Pass an explicit bundle path."
            case .platformsNotSpecified:
                "If you're not using Tuist projects, you must specify the platforms when inspecting an app by name, such as `tuist inspect bundle App --platforms ios`."
        #endif
        }
    }
}

public struct InspectBundleCommandService {
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling

    #if os(macOS)
        private let fileSystem: FileSysteming
        private let fileHandler: FileHandling
        private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
        private let manifestLoader: ManifestLoading
        private let manifestGraphLoader: ManifestGraphLoading
        private let userInputReader: UserInputReading
        private let defaultConfigurationFetcher: DefaultConfigurationFetching
    #endif

    public init(
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController()
    ) {
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController

        #if os(macOS)
            let manifestLoader = ManifestLoader.current
            self.fileSystem = FileSystem()
            self.fileHandler = FileHandler.shared
            self.xcodeProjectBuildDirectoryLocator = XcodeProjectBuildDirectoryLocator()
            self.manifestLoader = manifestLoader
            self.manifestGraphLoader = ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: []),
                graphMapper: SequentialGraphMapper([])
            )
            self.userInputReader = UserInputReader()
            self.defaultConfigurationFetcher = DefaultConfigurationFetcher()
        #endif
    }

    #if os(macOS)
        init(
            fileSystem: FileSysteming = FileSystem(),
            rosalind: Rosalindable = Rosalind(),
            createBundleService: CreateBundleServicing = CreateBundleService(),
            configLoader: ConfigLoading = ConfigLoader(),
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            gitController: GitControlling = GitController(),
            fileHandler: FileHandling = FileHandler.shared,
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating = XcodeProjectBuildDirectoryLocator(),
            manifestLoader: ManifestLoading = ManifestLoader.current,
            manifestGraphLoader: ManifestGraphLoading,
            userInputReader: UserInputReading = UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetching = DefaultConfigurationFetcher()
        ) {
            self.fileSystem = fileSystem
            self.rosalind = rosalind
            self.createBundleService = createBundleService
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.gitController = gitController
            self.fileHandler = fileHandler
            self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
            self.manifestLoader = manifestLoader
            self.manifestGraphLoader = manifestGraphLoader
            self.userInputReader = userInputReader
            self.defaultConfigurationFetcher = defaultConfigurationFetcher
        }
    #endif

    #if os(macOS)
        public func run(
            path: String?,
            bundle: String,
            configuration: String?,
            platforms: [Platform],
            derivedDataPath: String?,
            json: Bool
        ) async throws {
            let path = try await self.path(path)
            let bundlePath = try await resolveBundlePath(
                bundle,
                path: path,
                configuration: configuration,
                platforms: platforms,
                derivedDataPath: derivedDataPath
            )

            try await inspect(
                path: path,
                bundlePath: bundlePath,
                json: json
            )
        }
    #endif

    public func run(
        path: String?,
        bundle: String,
        json: Bool
    ) async throws {
        let bundlePath = try AbsolutePath(
            validating: bundle,
            relativeTo: try await Environment.current.currentWorkingDirectory()
        )
        let path = try await self.path(path)

        try await inspect(
            path: path,
            bundlePath: bundlePath,
            json: json
        )
    }

    private func inspect(
        path: AbsolutePath,
        bundlePath: AbsolutePath,
        json: Bool
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)

        if json {
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            let json = try appBundleReport.toJSON()
            Logger.current.info(
                .init(stringLiteral: json.toString(prettyPrint: true)),
                metadata: .json
            )
            return
        }

        guard let fullHandle = config.fullHandle else {
            throw InspectBundleCommandServiceError.missingFullHandle
        }

        let gitInfo = try gitController.gitInfo(workingDirectory: path)
        let gitRef = gitInfo.ref
        let gitBranch = gitInfo.branch
        let gitCommitSHA = gitInfo.sha

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let serverBundle = try await Noora.current.progressStep(
            message: "Analyzing bundle...",
            successMessage: "Bundle analyzed",
            errorMessage: nil,
            showSpinner: true
        ) { updateStep in
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            updateStep("Pushing bundle to the server...")
            return try await createBundleService.createBundle(
                fullHandle: fullHandle,
                serverURL: serverURL,
                appBundleReport: appBundleReport,
                gitCommitSHA: gitCommitSHA,
                gitBranch: gitBranch,
                gitRef: gitRef
            )
        }
        AlertController.current.success(
            .alert("View the bundle analysis at \(serverBundle.url)")
        )
    }

    #if os(macOS)
        private func resolveBundlePath(
            _ bundle: String,
            path: AbsolutePath,
            configuration: String?,
            platforms: [Platform],
            derivedDataPath: String?
        ) async throws -> AbsolutePath {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let explicitPath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

            if try await fileSystem.exists(explicitPath) {
                return explicitPath
            }

            let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
            if let fileExtension = explicitPath.extension, bundleExtensions.contains(fileExtension) {
                return explicitPath
            }

            let resolvedDerivedDataPath = try derivedDataPath.map {
                try AbsolutePath(validating: $0, relativeTo: fileHandler.currentPath)
            }

            if try await manifestLoader.hasRootManifest(at: path) {
                let config = try await configLoader.loadConfig(path: path)
                let (graph, _, _, _) = try await manifestGraphLoader.load(
                    path: path,
                    disableSandbox: config.project.disableSandbox
                )
                let graphTraverser = GraphTraverser(graph: graph)
                let matchingTargets = graphTraverser
                    .targets(product: .app)
                    .union(graphTraverser.targets(product: .appClip))
                    .union(graphTraverser.targets(product: .watch2App))
                    .filter { target in
                        target.target.name == bundle || target.target.productName == bundle
                    }
                    .sorted { $0.target.name < $1.target.name }

                guard !matchingTargets.isEmpty else {
                    let resolvedConfiguration = try defaultConfigurationFetcher.fetch(
                        configuration: configuration,
                        defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
                        graph: graph
                    )
                    throw InspectBundleCommandServiceError.noAppsFound(
                        app: bundle,
                        configuration: resolvedConfiguration
                    )
                }

                let appTarget: GraphTarget
                if matchingTargets.count == 1, let singleTarget = matchingTargets.first {
                    appTarget = singleTarget
                } else {
                    appTarget = try userInputReader.readValue(
                        asking: "Select the app that you want to inspect:",
                        values: matchingTargets,
                        valueDescription: \.target.name
                    )
                }

                let resolvedConfiguration = try defaultConfigurationFetcher.fetch(
                    configuration: configuration,
                    defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
                    graph: graph
                )
                let resolvedPlatforms = platforms.isEmpty ? appTarget.target.supportedPlatforms.map { $0 } : platforms

                return try await resolveBuiltAppPath(
                    app: appTarget.target.productName,
                    workspacePath: graph.workspace.xcWorkspacePath,
                    configuration: resolvedConfiguration,
                    platforms: resolvedPlatforms,
                    derivedDataPath: resolvedDerivedDataPath
                )
            } else {
                guard !platforms.isEmpty else {
                    throw InspectBundleCommandServiceError.platformsNotSpecified
                }

                let workspace = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"])
                    .collect()
                    .first
                let project = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"])
                    .collect()
                    .first

                guard let workspaceOrProjectPath = workspace ?? project else {
                    throw InspectBundleCommandServiceError.projectOrWorkspaceNotFound(path: path.pathString)
                }

                let resolvedConfiguration = configuration ?? BuildConfiguration.debug.name
                return try await resolveBuiltAppPath(
                    app: bundle,
                    workspacePath: workspaceOrProjectPath,
                    configuration: resolvedConfiguration,
                    platforms: platforms,
                    derivedDataPath: resolvedDerivedDataPath
                )
            }
        }

        private func resolveBuiltAppPath(
            app: String,
            workspacePath: AbsolutePath,
            configuration: String,
            platforms: [Platform],
            derivedDataPath: AbsolutePath?
        ) async throws -> AbsolutePath {
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
                    let buildDirectory = try await xcodeProjectBuildDirectoryLocator.locate(
                        destinationType: destinationType,
                        projectPath: workspacePath,
                        derivedDataPath: derivedDataPath,
                        configuration: configuration
                    )
                    let appPath = buildDirectory.appending(component: "\(app).app")
                    return try await fileSystem.exists(appPath) ? appPath : nil
                }

            guard !appPaths.isEmpty else {
                throw InspectBundleCommandServiceError.noAppsFound(app: app, configuration: configuration)
            }

            let uniquePaths = Array(Set(appPaths)).sorted { $0.pathString < $1.pathString }
            guard uniquePaths.count == 1, let bundlePath = uniquePaths.first else {
                throw InspectBundleCommandServiceError.multipleBuiltBundlesFound(
                    app: app,
                    paths: uniquePaths.map(\.pathString)
                )
            }

            return bundlePath
        }
    #endif

    private func path(_ path: String?) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if let path {
            return try AbsolutePath(
                validating: path, relativeTo: currentWorkingDirectory
            )
        } else {
            return currentWorkingDirectory
        }
    }
}
