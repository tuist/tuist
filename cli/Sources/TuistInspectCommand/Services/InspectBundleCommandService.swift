import FileSystem
import Foundation
import Noora
import Path
import Rosalind
import TuistAlert
import TuistConfigLoader
import TuistCore
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport
import TuistUserInputReader
import TuistXcodeBuildProducts
import XcodeGraph

public enum InspectBundleCommandServiceError: LocalizedError {
    case missingFullHandle
    case appleAppNameResolutionNotSupported
    case projectOrWorkspaceNotFound(path: String)
    case noAppsFound(app: String, configuration: String)
    case multipleBuiltBundlesFound(app: String, paths: [String])
    case platformsNotSpecified

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            "To analyze the app bundle, run 'tuist init' to connect to the Tuist server."
        case .appleAppNameResolutionNotSupported:
            "Resolving an app name for Apple platforms from Xcode build products is only supported on macOS. Pass an explicit bundle path instead."
        case let .projectOrWorkspaceNotFound(path):
            "Workspace or project not found at \(path)"
        case let .noAppsFound(app, configuration):
            "\(app) was not found in Xcode build products for the \(configuration) configuration. Build the app first or pass an explicit bundle path."
        case let .multipleBuiltBundlesFound(app, paths):
            "Multiple built bundles were found for \(app): \(paths.joined(separator: ", ")). Pass an explicit bundle path."
        case .platformsNotSpecified:
            "If you're not using Tuist projects, you must specify the platforms when inspecting an app by name, such as `tuist inspect bundle App --platforms ios`."
        }
    }
}

public struct InspectBundleCommandService {
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let fileSystem: FileSysteming
    private let fileHandler: FileHandling
    private let builtAppBundleLocator: BuiltAppBundleLocating
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private let userInputReader: UserInputReading
    private let defaultConfigurationFetcher: DefaultConfigurationFetching

    public init(
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController()
    ) {
        let manifestLoader = ManifestLoader.current
        self.init(
            rosalind: rosalind,
            createBundleService: createBundleService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            fileSystem: FileSystem(),
            fileHandler: FileHandler.shared,
            builtAppBundleLocator: BuiltAppBundleLocator(),
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: []),
                graphMapper: SequentialGraphMapper([])
            ),
            userInputReader: UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher()
        )
    }

    init(
        rosalind: Rosalindable,
        createBundleService: CreateBundleServicing,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        gitController: GitControlling,
        fileSystem: FileSysteming,
        fileHandler: FileHandling,
        builtAppBundleLocator: BuiltAppBundleLocating,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading,
        userInputReader: UserInputReading,
        defaultConfigurationFetcher: DefaultConfigurationFetching
    ) {
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.fileSystem = fileSystem
        self.fileHandler = fileHandler
        self.builtAppBundleLocator = builtAppBundleLocator
        self.manifestLoader = manifestLoader
        self.manifestGraphLoader = manifestGraphLoader
        self.userInputReader = userInputReader
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
    }

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

    private func resolveBundlePath(
        _ bundle: String,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?
    ) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let explicitPath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

        if try await fileSystem.exists(explicitPath) || looksLikeBundlePath(explicitPath) {
            return explicitPath
        }

        guard try await canResolveAppleAppNamesFromXcodeBuildProducts() else {
            throw InspectBundleCommandServiceError.appleAppNameResolutionNotSupported
        }

        let resolvedDerivedDataPath = try derivedDataPath.map {
            try AbsolutePath(validating: $0, relativeTo: fileHandler.currentPath)
        }

        if try await manifestLoader.hasRootManifest(at: path) {
            return try await resolveFromManifest(
                bundle: bundle,
                path: path,
                configuration: configuration,
                platforms: platforms,
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

            return try await resolveBuiltAppPath(
                app: bundle,
                workspacePath: workspaceOrProjectPath,
                configuration: configuration ?? BuildConfiguration.debug.name,
                platforms: platforms,
                derivedDataPath: resolvedDerivedDataPath
            )
        }
    }

    private func resolveFromManifest(
        bundle: String,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> AbsolutePath {
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

        let resolvedConfiguration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
            graph: graph
        )

        guard !matchingTargets.isEmpty else {
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

        let resolvedPlatforms = platforms.isEmpty ? appTarget.target.supportedPlatforms.map { $0 } : platforms
        return try await resolveBuiltAppPath(
            app: appTarget.target.productName,
            workspacePath: graph.workspace.xcWorkspacePath,
            configuration: resolvedConfiguration,
            platforms: resolvedPlatforms,
            derivedDataPath: derivedDataPath
        )
    }

    private func resolveBuiltAppPath(
        app: String,
        workspacePath: AbsolutePath,
        configuration: String,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> AbsolutePath {
        do {
            return try await builtAppBundleLocator.locateBuiltAppBundlePath(
                app: app,
                projectPath: workspacePath,
                derivedDataPath: derivedDataPath,
                configuration: configuration,
                platforms: platforms
            )
        } catch let error as BuiltAppBundleLocatorError {
            switch error {
            case let .noAppsFound(app, configuration):
                throw InspectBundleCommandServiceError.noAppsFound(app: app, configuration: configuration)
            case let .multipleBuiltBundlesFound(app, paths):
                throw InspectBundleCommandServiceError.multipleBuiltBundlesFound(app: app, paths: paths)
            }
        }
    }

    private func canResolveAppleAppNamesFromXcodeBuildProducts() async throws -> Bool {
        try await fileSystem.exists(try AbsolutePath(validating: "/usr/bin/xcodebuild"))
    }

    private func looksLikeBundlePath(_ path: AbsolutePath) -> Bool {
        let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
        guard let fileExtension = path.extension else { return false }
        return bundleExtensions.contains(fileExtension)
    }

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
