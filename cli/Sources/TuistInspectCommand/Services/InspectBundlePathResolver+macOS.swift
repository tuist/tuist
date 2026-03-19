#if os(macOS)
    import FileSystem
    import Foundation
    import Path
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistLoader
    import TuistSimulator
    import TuistSupport
    import TuistUserInputReader
    import TuistXcodeBuildProducts
    import XcodeGraph

    struct AppleInspectBundlePathResolver: InspectBundlePathResolving {
        private let fileSystem: FileSysteming
        private let fileHandler: FileHandling
        private let builtAppBundleLocator: BuiltAppBundleLocating
        private let configLoader: ConfigLoading
        private let manifestLoader: ManifestLoading
        private let manifestGraphLoader: ManifestGraphLoading
        private let userInputReader: UserInputReading
        private let defaultConfigurationFetcher: DefaultConfigurationFetching

        init(
            fileSystem: FileSysteming = FileSystem(),
            fileHandler: FileHandling = FileHandler.shared,
            builtAppBundleLocator: BuiltAppBundleLocating = BuiltAppBundleLocator(),
            configLoader: ConfigLoading = ConfigLoader(),
            manifestLoader: ManifestLoading = ManifestLoader.current,
            manifestGraphLoader: ManifestGraphLoading,
            userInputReader: UserInputReading = UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetching = DefaultConfigurationFetcher()
        ) {
            self.fileSystem = fileSystem
            self.fileHandler = fileHandler
            self.builtAppBundleLocator = builtAppBundleLocator
            self.configLoader = configLoader
            self.manifestLoader = manifestLoader
            self.manifestGraphLoader = manifestGraphLoader
            self.userInputReader = userInputReader
            self.defaultConfigurationFetcher = defaultConfigurationFetcher
        }

        func resolve(
            bundle: String,
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

        private func looksLikeBundlePath(_ path: AbsolutePath) -> Bool {
            let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
            guard let fileExtension = path.extension else { return false }
            return bundleExtensions.contains(fileExtension)
        }
    }

    func makeInspectBundlePathResolver() -> any InspectBundlePathResolving {
        let manifestLoader = ManifestLoader.current
        return AppleInspectBundlePathResolver(
            manifestLoader: manifestLoader,
            manifestGraphLoader: ManifestGraphLoader(
                manifestLoader: manifestLoader,
                workspaceMapper: SequentialWorkspaceMapper(mappers: []),
                graphMapper: SequentialGraphMapper([])
            )
        )
    }
#endif
