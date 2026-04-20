import FileSystem
import Foundation
import Mockable
import Path
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistSupport
import TuistUserInputReader
import XcodeGraph

public struct ResolvedAppBundleTarget: Sendable {
    public let app: String
    public let workspacePath: AbsolutePath
    public let configuration: String
    public let platforms: [Platform]
    public let derivedDataPath: AbsolutePath?

    public init(
        app: String,
        workspacePath: AbsolutePath,
        configuration: String,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) {
        self.app = app
        self.workspacePath = workspacePath
        self.configuration = configuration
        self.platforms = platforms
        self.derivedDataPath = derivedDataPath
    }
}

public enum AppBundleTargetResolverError: Equatable, LocalizedError {
    case appNotSpecified
    case projectOrWorkspaceNotFound(path: String)
    case noAppsFound(app: String, configuration: String)
    case platformsNotSpecified

    public var errorDescription: String? {
        switch self {
        case .appNotSpecified:
            "If you're not using Tuist projects, you must specify the app name, such as `App --platforms ios`."
        case let .projectOrWorkspaceNotFound(path):
            "Workspace or project not found at \(path)"
        case let .noAppsFound(app, configuration):
            "\(app) was not found in Xcode build products for the \(configuration) configuration. Build the app first or pass an explicit bundle path."
        case .platformsNotSpecified:
            "You must specify the platforms when resolving an app by name, such as `--platforms ios`."
        }
    }
}

@Mockable
public protocol AppBundleTargetResolving {
    func resolve(
        app: String?,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> ResolvedAppBundleTarget
}

public struct AppBundleTargetResolver: AppBundleTargetResolving {
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private let configLoader: ConfigLoading
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let userInputReader: UserInputReading
    private let fileSystem: FileSysteming

    public init(
        manifestLoader: ManifestLoading = ManifestLoader.current,
        manifestGraphLoader: ManifestGraphLoading? = nil,
        configLoader: ConfigLoading = ConfigLoader(),
        defaultConfigurationFetcher: DefaultConfigurationFetching = DefaultConfigurationFetcher(),
        userInputReader: UserInputReading = UserInputReader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.manifestLoader = manifestLoader
        let resolvedManifestGraphLoader = manifestGraphLoader ?? ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        self.manifestGraphLoader = resolvedManifestGraphLoader
        self.configLoader = configLoader
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.userInputReader = userInputReader
        self.fileSystem = fileSystem
    }

    public func resolve(
        app: String?,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> ResolvedAppBundleTarget {
        if try await manifestLoader.hasRootManifest(at: path) {
            return try await resolveFromManifest(
                app: app,
                path: path,
                configuration: configuration,
                platforms: platforms,
                derivedDataPath: derivedDataPath
            )
        } else {
            return try await resolveFromXcodeProject(
                app: app,
                path: path,
                configuration: configuration,
                platforms: platforms,
                derivedDataPath: derivedDataPath
            )
        }
    }

    private func resolveFromManifest(
        app: String?,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> ResolvedAppBundleTarget {
        let config = try await configLoader.loadConfig(path: path)
        let (graph, _, _, _) = try await manifestGraphLoader.load(
            path: path,
            disableSandbox: config.project.disableSandbox
        )
        let graphTraverser = GraphTraverser(graph: graph)
        let appTargets = graphTraverser
            .targets(product: .app)
            .union(graphTraverser.targets(product: .appClip))
            .union(graphTraverser.targets(product: .watch2App))
            .filter { target in
                if let app {
                    return target.target.name == app || target.target.productName == app
                }
                return true
            }
            .sorted { $0.target.name < $1.target.name }

        let resolvedConfiguration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
            graph: graph
        )

        guard !appTargets.isEmpty else {
            throw AppBundleTargetResolverError.noAppsFound(
                app: app ?? "",
                configuration: resolvedConfiguration
            )
        }

        let appTarget: GraphTarget
        if appTargets.count == 1, let single = appTargets.first {
            appTarget = single
        } else {
            appTarget = try userInputReader.readValue(
                asking: "Select the app:",
                values: appTargets,
                valueDescription: \.target.name
            )
        }

        let resolvedPlatforms = platforms.isEmpty
            ? appTarget.target.supportedPlatforms.map { $0 }
            : platforms

        return ResolvedAppBundleTarget(
            app: appTarget.target.productName,
            workspacePath: graph.workspace.xcWorkspacePath,
            configuration: resolvedConfiguration,
            platforms: resolvedPlatforms,
            derivedDataPath: derivedDataPath
        )
    }

    private func resolveFromXcodeProject(
        app: String?,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: AbsolutePath?
    ) async throws -> ResolvedAppBundleTarget {
        guard let app else {
            throw AppBundleTargetResolverError.appNotSpecified
        }

        guard !platforms.isEmpty else {
            throw AppBundleTargetResolverError.platformsNotSpecified
        }

        let workspace = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"])
            .collect()
            .first
        let project = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"])
            .collect()
            .first

        guard let workspacePath = workspace ?? project else {
            throw AppBundleTargetResolverError.projectOrWorkspaceNotFound(path: path.pathString)
        }

        return ResolvedAppBundleTarget(
            app: app,
            workspacePath: workspacePath,
            configuration: configuration ?? BuildConfiguration.debug.name,
            platforms: platforms,
            derivedDataPath: derivedDataPath
        )
    }
}
