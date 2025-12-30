import FileSystem
import Foundation
import Logging
import Path
import TuistAutomation
import TuistCache
import TuistCore
import TuistLoader
import TuistPlugin
import TuistServer
import TuistSupport
import TuistXCActivityLog
import XcodeGraph
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif
public protocol CacheServicing {
    func run(
        path directory: String?,
        configuration: String?,
        targetsToBinaryCache: Set<String>,
        externalOnly: Bool,
        generateOnly: Bool
    ) async throws
}

final class EmptyCacheService: CacheServicing {
    func run(
        path _: String?,
        configuration _: String?,
        targetsToBinaryCache _: Set<String>,
        externalOnly _: Bool,
        generateOnly _: Bool
    ) async throws {
        Logger.current
            .notice(
                "Caching is currently not opensourced. Please, report issues with caching on GitHub and the Tuist team will take a look."
            )
    }
}

#if canImport(TuistCacheEE)

    // swiftlint:disable:next type_body_length
    struct CacheService: CacheServicing {
        enum Destination {
            case simulator
            case device
        }

        private let configLoader: ConfigLoading
        private let manifestLoader: ManifestLoading
        private let pluginService: PluginServicing
        private let generatorFactory: CacheGeneratorFactorying
        private let cacheWarmGraphLinter: CacheWarmGraphLinting
        private let cacheBuiltArtifactsFetcher: CacheBuiltArtifactsFetching
        private let defaultConfigurationFetcher: DefaultConfigurationFetching
        private let simulatorController: SimulatorControlling
        private let xcodeBuildController: XcodeBuildControlling
        private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
        private let fileHandler: FileHandling
        private let fileSystem: FileSysteming
        private let contentHasher: ContentHashing
        private let cacheGraphContentHasher: CacheGraphContentHashing
        private let activityLogController: XCActivityLogControlling

        init() {
            let contentHasher = ContentHasher()
            self.init(
                generatorFactory: CacheGeneratorFactory(contentHasher: contentHasher),
                cacheWarmGraphLinter: CacheWarmGraphLinter(),
                cacheBuiltArtifactsFetcher: CacheBuiltArtifactsFetcher(),
                defaultConfigurationFetcher: DefaultConfigurationFetcher(),
                xcodeBuildController: XcodeBuildController(),
                simulatorController: SimulatorController(),
                xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
                fileHandler: FileHandler.shared,
                fileSystem: FileSystem(),
                contentHasher: contentHasher,
                cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
                activityLogController: XCActivityLogController()
            )
        }

        init(
            generatorFactory: CacheGeneratorFactorying,
            cacheWarmGraphLinter: CacheWarmGraphLinting,
            cacheBuiltArtifactsFetcher: CacheBuiltArtifactsFetching,
            defaultConfigurationFetcher: DefaultConfigurationFetching,
            xcodeBuildController: XcodeBuildControlling,
            simulatorController: SimulatorControlling,
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
            fileHandler: FileHandling,
            fileSystem: FileSysteming,
            contentHasher: ContentHashing,
            cacheGraphContentHasher: CacheGraphContentHashing,
            activityLogController: XCActivityLogControlling
        ) {
            configLoader = ConfigLoader(manifestLoader: ManifestLoader())
            manifestLoader = ManifestLoader()
            pluginService = PluginService()
            self.generatorFactory = generatorFactory
            self.cacheWarmGraphLinter = cacheWarmGraphLinter
            self.cacheBuiltArtifactsFetcher = cacheBuiltArtifactsFetcher
            self.defaultConfigurationFetcher = defaultConfigurationFetcher
            self.xcodeBuildController = xcodeBuildController
            self.simulatorController = simulatorController
            self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
            self.fileHandler = fileHandler
            self.fileSystem = fileSystem
            self.contentHasher = contentHasher
            self.cacheGraphContentHasher = cacheGraphContentHasher
            self.activityLogController = activityLogController
        }

        // swiftlint:disable:next function_body_length
        func run(
            path directory: String?,
            configuration: String?,
            targetsToBinaryCache: Set<String>,
            externalOnly: Bool,
            generateOnly: Bool
        ) async throws {
            let path = if let directory {
                try AbsolutePath(validating: directory, relativeTo: fileHandler.currentPath)
            } else {
                fileHandler.currentPath
            }
            let config = try await configLoader.loadConfig(path: path)
            let cacheStorage = try await CacheStorageFactory().cacheStorage(config: config)
            let generator = generatorFactory.binaryCacheWarmingPreload(
                config: config,
                targetsToBinaryCache: Set(targetsToBinaryCache.map { TargetQuery(stringLiteral: $0) })
            )

            // The loading of the graph triggers the fetching of remote binaries into the local cache to speed up warming.
            // Because we only need to pull the binaries, we don't generate a project in this step.
            let graph = try await generator.load(path: path, options: config.project.generatedProject?.generationOptions)

            let configuration = try defaultConfigurationFetcher.fetch(
                configuration: configuration,
                defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
                graph: graph
            )
            let isReleaseConfiguration = graph.projects.values.flatMap(\.settings.configurations.keys)
                .first(where: { $0.name == configuration })?.variant == .release

            // Lint
            try cacheWarmGraphLinter.lint(graph: graph)

            // Hash
            Logger.current.info("Hashing cacheable targets")

            let cacheableTargets = try await cacheableTargets(
                for: graph,
                configuration: configuration,
                config: config,
                includedTargets: targetsToBinaryCache,
                externalOnly: externalOnly,
                cacheStorage: cacheStorage
            )

            let cacheableTargetNames = Set(cacheableTargets.map(\.0.target.name))
            guard !cacheableTargets.isEmpty else {
                Logger.current.info("All cacheable targets are already cached")
                return
            }

            Logger.current
                .notice("Targets to be cached: \(cacheableTargetNames.sorted().joined(separator: ", "))")

            let targetsToBinaryCache = cacheableTargets.reduce(into: [Platform: Set<TargetQuery>]()) { acc, next in
                for platform in next.0.target.supportedPlatforms {
                    var platformTargets = acc[platform, default: Set()]
                    platformTargets.insert(TargetQuery(stringLiteral: next.0.target.name))
                    acc[platform] = platformTargets
                }
            }
            let (projectPath, updatedGraph, _) = try await generatorFactory
                .binaryCacheWarming(
                    config: config,
                    targetsToBinaryCache: targetsToBinaryCache,
                    configuration: configuration,
                    cacheStorage: cacheStorage
                )
                .generateWithGraph(path: path, options: config.project.generatedProject?.generationOptions)

            if generateOnly {
                return
            }

            Logger.current.info("Building cacheable targets")

            try await archive(
                updatedGraph,
                projectPath: projectPath,
                configuration: configuration,
                hashesByTargetToBeCached: cacheableTargets,
                cacheStorage: cacheStorage,
                isReleaseConfiguration: isReleaseConfiguration
            )

            Logger.current.info(
                "All cacheable targets have been cached successfully as xcframeworks",
                metadata: .success
            )
        }

        // swiftlint:disable:next function_body_length
        private func archive(
            _ graph: Graph,
            projectPath: AbsolutePath,
            configuration: String,
            hashesByTargetToBeCached: [(GraphTarget, String)],
            cacheStorage: CacheStoring,
            isReleaseConfiguration: Bool
        ) async throws {
            let binariesSchemes = graph.workspace.schemes
                .filter { $0.name.contains("Binaries-Cache") && $0.name != "Binaries-Cache-Catalyst" }
                .filter { !($0.buildAction?.targets ?? []).isEmpty }
                .map { (scheme: $0, cacheOutputType: CacheOutputType.xcframework) }

            let catalystScheme = graph.workspace.schemes
                .first { $0.name == "Binaries-Cache-Catalyst" && !($0.buildAction?.targets ?? []).isEmpty }

            let bundlesSchemes = graph.workspace.schemes
                .filter { $0.name.contains("Bundles-Cache") }
                .filter { !($0.buildAction?.targets ?? []).isEmpty }
                .map { (scheme: $0, cacheOutputType: CacheOutputType.bundle) }

            let macroSchemes = graph.workspace.schemes
                .filter { $0.name.contains("Macros-Cache") }
                .filter { !($0.buildAction?.targets ?? []).isEmpty }
                .map { (scheme: $0, cacheOutputType: CacheOutputType.xcframework) }

            try await FileHandler.shared.inTemporaryDirectory { temporaryDirectory in
                var artifactsToStore: [CacheGraphTargetBuiltArtifact] = []

                let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
                let activityLogsDirectory = temporaryDirectory.appending(component: "activity-logs")

                try fileHandler.createFolder(derivedDataPath)
                try fileHandler.createFolder(activityLogsDirectory)

                let xcodebuildTarget = XcodeBuildTarget(with: projectPath)

                var binaryArtifactDirectories: [Platform: Set<AbsolutePath>] = [:]
                for (scheme, _) in binariesSchemes {
                    try await buildBinarySchemes(
                        scheme,
                        configuration: configuration,
                        xcodebuildTarget: xcodebuildTarget,
                        graph: graph,
                        binaryArtifactDirectories: &binaryArtifactDirectories,
                        temporaryDirectory: temporaryDirectory,
                        derivedDataPath: derivedDataPath,
                        isReleaseConfiguration: isReleaseConfiguration
                    )
                }

                if let catalystScheme {
                    try await buildCatalystScheme(
                        catalystScheme,
                        configuration: configuration,
                        xcodebuildTarget: xcodebuildTarget,
                        binaryArtifactDirectories: &binaryArtifactDirectories,
                        temporaryDirectory: temporaryDirectory,
                        derivedDataPath: derivedDataPath,
                        isReleaseConfiguration: isReleaseConfiguration
                    )
                }

                try await moveActivityLogs(derivedDataPath: derivedDataPath, activityLogsDirectory: activityLogsDirectory)

                for (scheme, _) in bundlesSchemes {
                    artifactsToStore.append(contentsOf: try await buildBundles(
                        scheme,
                        configuration: configuration,
                        xcodebuildTarget: xcodebuildTarget,
                        derivedDataPath: derivedDataPath,
                        cacheableTargets: hashesByTargetToBeCached
                    ))
                }

                try await moveActivityLogs(derivedDataPath: derivedDataPath, activityLogsDirectory: activityLogsDirectory)

                for (scheme, _) in macroSchemes {
                    artifactsToStore.append(contentsOf: try await buildMacros(
                        scheme,
                        configuration: configuration,
                        xcodebuildTarget: xcodebuildTarget,
                        derivedDataPath: derivedDataPath,
                        cacheableTargets: hashesByTargetToBeCached,
                        temporaryDirectory: temporaryDirectory
                    ))
                }

                try await moveActivityLogs(derivedDataPath: derivedDataPath, activityLogsDirectory: activityLogsDirectory)

                Logger.current.info("Creating XCFrameworks", metadata: .section)
                artifactsToStore.append(contentsOf: try await buildXCFrameworks(
                    cacheableTargets: hashesByTargetToBeCached,
                    binaryArtifactDirectories: binaryArtifactDirectories,
                    temporaryDirectory: temporaryDirectory
                ))

                Logger.current.info("Storing binaries to speed up workflows", metadata: .section)

                let successfullyStoredTargets = try await store(
                    try await artifactsWithBuildTimes(
                        artifacts: artifactsToStore,
                        projectDerivedDataDirectory: derivedDataPath,
                        activityLogsDirectory: activityLogsDirectory
                    ),
                    cacheStorage: cacheStorage,
                    temporaryDirectory: temporaryDirectory
                )

                let targetsStored = successfullyStoredTargets.map(\.name).sorted().joined(separator: ", ")
                if successfullyStoredTargets.isEmpty {
                    Logger.current.info("No targets were stored")
                } else if successfullyStoredTargets.count == 1 {
                    Logger.current.info("\(successfullyStoredTargets.count) target stored: \(targetsStored)")
                } else {
                    Logger.current.info("\(successfullyStoredTargets.count) targets stored: \(targetsStored)")
                }
            }
        }

        /// xcodebuild invocations might delete old activity logs, so to prevent that from happening, we copy them into a
        /// temporary
        /// directory.
        private func moveActivityLogs(derivedDataPath: AbsolutePath, activityLogsDirectory: AbsolutePath) async throws {
            let activityLogs = try await fileSystem.glob(directory: derivedDataPath, include: ["Logs/Build/*.xcactivitylog"])
                .collect()
            for activityLog in activityLogs {
                try await fileSystem.move(from: activityLog, to: activityLogsDirectory.appending(component: activityLog.basename))
            }
        }

        private func productsDirectory(
            platform: Platform,
            configuration: String,
            destination: Destination = .simulator,
            isMacCatalystVariant: Bool = false
        ) -> String {
            guard platform != .macOS else {
                return configuration
            }
            if isMacCatalystVariant {
                return "\(configuration)-maccatalyst"
            }
            switch destination {
            case .simulator:
                return "\(configuration)-\(platform.xcodeSimulatorSDK!)"
            case .device:
                return "\(configuration)-\(platform.xcodeDeviceSDK)"
            }
        }

        private func buildMacros(
            _ scheme: Scheme,
            configuration: String,
            xcodebuildTarget: XcodeBuildTarget,
            derivedDataPath: AbsolutePath,
            cacheableTargets: [(GraphTarget, String)],
            temporaryDirectory: AbsolutePath
        ) async throws -> [CacheGraphTargetBuiltArtifact] {
            Logger.current.notice("Building scheme \(scheme.name)", metadata: .subsection)
            let arguments: [XcodeBuildArgument] = [
                .xcarg("SKIP_INSTALL", "NO"),
                .configuration(configuration),
                .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                .xcarg("CODE_SIGN_IDENTITY", ""),
                .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
                .xcarg("CODE_SIGNING_ALLOWED", "NO"),
                .xcarg("CODE_SIGNING_REQUIRED", "NO"),
            ]
            try await xcodeBuildController.build(
                xcodebuildTarget,
                scheme: scheme.name,
                destination: nil,
                rosetta: false,
                derivedDataPath: derivedDataPath,
                clean: false,
                arguments: arguments,
                passthroughXcodeBuildArguments: [
                    "-resultBundlePath",
                    derivedDataPath.appending(component: UUID().uuidString).pathString,
                ]
            )

            var macrosToStore: [CacheGraphTargetBuiltArtifact] = []

            for macro in cacheableTargets.filter({ $0.0.target.product == .macro }) {
                let macroPath = derivedDataPath.appending(components: [
                    "Build",
                    "Products",
                    configuration,
                    macro.0.target.productName,
                ])
                guard try await fileSystem.exists(macroPath) else { continue }
                // This will help us identify in the storage whether an executable represents or not a macro.
                let macroWithExtension = temporaryDirectory.appending(component: "\(macroPath.basename).macro")
                try fileHandler.copy(from: macroPath, to: macroWithExtension)
                macrosToStore.append(CacheGraphTargetBuiltArtifact(
                    type: .macro,
                    graphTarget: macro.0,
                    hash: macro.1,
                    path: macroWithExtension,
                    metadata: .init()
                ))
            }

            return macrosToStore
        }

        private func buildBundles(
            _ scheme: Scheme,
            configuration: String,
            xcodebuildTarget: XcodeBuildTarget,
            derivedDataPath: AbsolutePath,
            cacheableTargets: [(GraphTarget, String)]
        ) async throws -> [CacheGraphTargetBuiltArtifact] {
            var bundlesToStore: [CacheGraphTargetBuiltArtifact] = []

            Logger.current.notice("Building scheme \(scheme.name)", metadata: .subsection)

            let platform = Platform.allCases.first { scheme.name.hasSuffix($0.caseValue) }!

            var arguments: [XcodeBuildArgument] = [
                .xcarg("SKIP_INSTALL", "NO"),
                .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                .xcarg("CODE_SIGN_IDENTITY", ""),
                .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
                .xcarg("CODE_SIGNING_ALLOWED", "NO"),
                .xcarg("CODE_SIGNING_REQUIRED", "NO"),
                .configuration(configuration),
            ]
            // We currently skip building for maccatalyst as we prefer to generate a bundle for iOS instead.
            // iOS bundles should be compatible with maccatalyst ones
//        let macCatalystSupportedTargets = macCatalystTargets(graph: graph, scheme: scheme)
//        let buildsForMacCatalyst = buildsForMacCatalyst(graph: graph, scheme: scheme)
//        if platform == .iOS, !macCatalystSupportedTargets.isEmpty, buildsForMacCatalyst {
//            arguments.append(.destination("platform=macOS,variant=Mac Catalyst"))
//        }
            if platform.hasSimulators {
                arguments.append(.destination("generic/platform=\(platform.caseValue) Simulator"))
            } else if platform == .macOS {
                // no arguments added
            } else {
                arguments.append(.destination("generic/platform=\(platform.caseValue)"))
            }
            try await xcodeBuildController.build(
                xcodebuildTarget,
                scheme: scheme.name,
                destination: nil,
                rosetta: false,
                derivedDataPath: derivedDataPath,
                clean: false,
                arguments: arguments,
                passthroughXcodeBuildArguments: [
                    "-resultBundlePath",
                    derivedDataPath.appending(component: UUID().uuidString).pathString,
                ]
            )

            // NOTE: This logic doesn't account for multi-platform bundle targets.
            // If there's a bundle target for multiple platforms the bundle that we'll end persisting is the one for the last
            // platform
            // that we build.
            let bundleProductsDirectory = derivedDataPath
                .appending(
                    try RelativePath(
                        validating: "Build/Products/\(productsDirectory(platform: platform, configuration: configuration))"
                    )
                )
            for bundle in cacheableTargets.filter({ $0.0.target.product == .bundle }) {
                let bundlePath = bundleProductsDirectory.appending(component: bundle.0.target.productNameWithExtension)
                guard try await fileSystem.exists(bundlePath) else { continue }
                bundlesToStore.append(CacheGraphTargetBuiltArtifact(
                    type: .bundle,
                    graphTarget: bundle.0,
                    hash: bundle.1,
                    path: bundlePath,
                    metadata: .init()
                ))
            }

            return bundlesToStore
        }

        private func buildXCFrameworks(
            cacheableTargets: [(GraphTarget, String)],
            binaryArtifactDirectories: [Platform: Set<AbsolutePath>],
            temporaryDirectory: AbsolutePath
        ) async throws -> [CacheGraphTargetBuiltArtifact] {
            var xcframeworks: [CacheGraphTargetBuiltArtifact] = []
            let cacheableTargets = cacheableTargets.filter(\.0.target.product.isFramework)

            for cacheableTarget in cacheableTargets {
                let platforms = Array(cacheableTarget.0.target.supportedPlatforms)
                let platformBinaryArtifacts = platforms.flatMap { Array(binaryArtifactDirectories[$0, default: Set()]) }
                let artifactsIncludingTarget = try await platformBinaryArtifacts.concurrentCompactMap {
                    let artifactPath = $0.appending(components: [cacheableTarget.0.target.productNameWithExtension])
                    return try await fileSystem.exists(artifactPath) ? artifactPath : nil
                }

                let xcframeworkPath = temporaryDirectory.appending(components: [
                    "xcframeworks",
                    "\(cacheableTarget.0.target.name).xcframework",
                ])

                let xcodebuildArguments: [String] = artifactsIncludingTarget
                    .flatMap { artifactPath in
                        ["-framework", artifactPath.pathString]
                    } + ["-allow-internal-distribution"]

                Logger.current.info("Creating XCFramework for \(cacheableTarget.0.target.name)", metadata: .section)

                try await xcodeBuildController.createXCFramework(
                    arguments: xcodebuildArguments,
                    output: xcframeworkPath
                )

                xcframeworks.append(CacheGraphTargetBuiltArtifact(
                    type: .xcframework,
                    graphTarget: cacheableTarget.0,
                    hash: cacheableTarget.1,
                    path: xcframeworkPath,
                    metadata: .init()
                ))
            }

            return xcframeworks
        }

        // swiftlint:disable:next function_body_length
        private func buildBinarySchemes(
            _ scheme: Scheme,
            configuration: String,
            xcodebuildTarget: XcodeBuildTarget,
            graph _: Graph,
            binaryArtifactDirectories: inout [Platform: Set<AbsolutePath>],
            temporaryDirectory: AbsolutePath,
            derivedDataPath: AbsolutePath,
            isReleaseConfiguration: Bool
        ) async throws {
            let platform = Platform.allCases.first { scheme.name.hasSuffix($0.caseValue) }!
            let platformArtifactsDirectory = temporaryDirectory.appending(components: ["artifacts", "\(platform.caseValue)"])

            try fileHandler.createFolder(platformArtifactsDirectory)

            // Simulator
            if platform.hasSimulators {
                let simulatorArtifactsDirectory = platformArtifactsDirectory.appending(component: "simulator")
                try fileHandler.createFolder(simulatorArtifactsDirectory)

                Logger.current.info("Building scheme \(scheme.name) for the simulator", metadata: .section)
                try await xcodeBuildController.build(
                    xcodebuildTarget,
                    scheme: scheme.name,
                    destination: nil,
                    rosetta: false,
                    derivedDataPath: derivedDataPath,
                    clean: false,
                    arguments: [
                        .destination("generic/platform=\(platform.caseValue) Simulator"),
                        .xcarg("SKIP_INSTALL", "NO"),
                        .xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
                        .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                        .xcarg("CODE_SIGN_IDENTITY", ""),
                        .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
                        .xcarg("CODE_SIGNING_ALLOWED", "NO"),
                        .xcarg("CODE_SIGNING_REQUIRED", "NO"),
                        .xcarg("COMPILER_INDEX_STORE_ENABLE", "NO"),
                        .configuration(configuration),
                        // To prevent the rejection when publishing on the App Store
                        // https://developer.apple.com/library/archive/qa/qa1964/_index.html
                    ] + (isReleaseConfiguration ? [
                        .xcarg("GCC_INSTRUMENT_PROGRAM_FLOW_ARCS", "NO"),
                        .xcarg("CLANG_ENABLE_CODE_COVERAGE", "NO"),
                    ] : []),
                    passthroughXcodeBuildArguments: [
                        "-resultBundlePath",
                        derivedDataPath.appending(component: UUID().uuidString).pathString,
                    ]
                )

                let productsDirectory = derivedDataPath
                    .appending(
                        // swiftlint:disable:next force_try
                        try RelativePath(
                            validating: "Build/Products/\(productsDirectory(platform: platform, configuration: configuration, destination: .simulator))"
                        )
                    )
                try await copyDerivedDataArtifacts(
                    into: simulatorArtifactsDirectory,
                    productsDirectory: productsDirectory,
                    platform: platform,
                    binaryArtifactDirectories: &binaryArtifactDirectories
                )
            }

            // Device
            Logger.current.info("Building scheme \(scheme.name) for device", metadata: .section)

            let deviceArtifactsDirectory = platformArtifactsDirectory.appending(component: "device")
            try fileHandler.createFolder(deviceArtifactsDirectory)

            var deviceArguments: [XcodeBuildArgument] = [
                .xcarg("SKIP_INSTALL", "NO"),
                .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                .xcarg("CODE_SIGN_IDENTITY", ""),
                .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
                .xcarg("CODE_SIGNING_ALLOWED", "NO"),
                .xcarg("CODE_SIGNING_REQUIRED", "NO"),
                .xcarg("COMPILER_INDEX_STORE_ENABLE", "NO"),
                .configuration(configuration),
                // To prevent the rejection when publishing on the App Store
                // https://developer.apple.com/library/archive/qa/qa1964/_index.html
            ] + (isReleaseConfiguration ? [
                .xcarg("GCC_INSTRUMENT_PROGRAM_FLOW_ARCS", "NO"),
                .xcarg("CLANG_ENABLE_CODE_COVERAGE", "NO"),
            ] : [])
            if platform == .macOS {
                deviceArguments.append(contentsOf: [
                    .xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
                    .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                ])
            } else {
                deviceArguments.append(.destination("generic/platform=\(platform.caseValue)"))
            }

            try await xcodeBuildController.build(
                xcodebuildTarget,
                scheme: scheme.name,
                destination: nil,
                rosetta: false,
                derivedDataPath: derivedDataPath,
                clean: false,
                arguments: deviceArguments,
                passthroughXcodeBuildArguments: [
                    "-resultBundlePath",
                    derivedDataPath.appending(component: UUID().uuidString).pathString,
                ]
            )

            let productsDirectory = derivedDataPath
                .appending(
                    // swiftlint:disable:next force_try
                    try RelativePath(
                        validating: "Build/Products/\(productsDirectory(platform: platform, configuration: configuration, destination: .device))"
                    )
                )

            try await copyDerivedDataArtifacts(
                into: deviceArtifactsDirectory,
                productsDirectory: productsDirectory,
                platform: platform,
                binaryArtifactDirectories: &binaryArtifactDirectories
            )
        }

        private func buildCatalystScheme(
            _ scheme: Scheme,
            configuration: String,
            xcodebuildTarget: XcodeBuildTarget,
            binaryArtifactDirectories: inout [Platform: Set<AbsolutePath>],
            temporaryDirectory: AbsolutePath,
            derivedDataPath: AbsolutePath,
            isReleaseConfiguration: Bool
        ) async throws {
            let platformArtifactsDirectory = temporaryDirectory.appending(components: ["artifacts", "iOS"])
            try fileHandler.createFolder(platformArtifactsDirectory)

            Logger.current.info("Building scheme \(scheme.name) for Mac Catalyst", metadata: .section)

            let macCatalystArtifactsDirectory = platformArtifactsDirectory.appending(component: "mac-catalyst")
            try fileHandler.createFolder(macCatalystArtifactsDirectory)

            try await xcodeBuildController.build(
                xcodebuildTarget,
                scheme: scheme.name,
                destination: nil,
                rosetta: false,
                derivedDataPath: derivedDataPath,
                clean: false,
                arguments: [
                    .destination("generic/platform=macOS,variant=Mac Catalyst"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
                    .xcarg("ONLY_ACTIVE_ARCH", "NO"),
                    .xcarg("CODE_SIGN_IDENTITY", ""),
                    .xcarg("CODE_SIGN_ENTITLEMENTS", ""),
                    .xcarg("CODE_SIGNING_ALLOWED", "NO"),
                    .xcarg("CODE_SIGNING_REQUIRED", "NO"),
                    .xcarg("COMPILER_INDEX_STORE_ENABLE", "NO"),
                    .configuration(configuration),
                ] + (isReleaseConfiguration ? [
                    .xcarg("GCC_INSTRUMENT_PROGRAM_FLOW_ARCS", "NO"),
                    .xcarg("CLANG_ENABLE_CODE_COVERAGE", "NO"),
                ] : []),
                passthroughXcodeBuildArguments: [
                    "-resultBundlePath",
                    derivedDataPath.appending(component: UUID().uuidString).pathString,
                ]
            )

            let productsDirectory = derivedDataPath
                .appending(
                    try RelativePath(
                        validating: "Build/Products/\(productsDirectory(platform: .iOS, configuration: configuration, destination: .device, isMacCatalystVariant: true))"
                    )
                )
            try await copyDerivedDataArtifacts(
                into: macCatalystArtifactsDirectory,
                productsDirectory: productsDirectory,
                platform: .iOS,
                binaryArtifactDirectories: &binaryArtifactDirectories
            )
        }

        private func artifactsWithBuildTimes(
            artifacts: [CacheGraphTargetBuiltArtifact],
            projectDerivedDataDirectory _: AbsolutePath,
            xcresultPaths _: [AbsolutePath] = [],
            activityLogsDirectory: AbsolutePath,
        ) async throws -> [CacheGraphTargetBuiltArtifact] {
            let activityLogs = try await fileSystem.glob(directory: activityLogsDirectory, include: ["*.xcactivitylog"]).collect()
            let buildTimes = try await activityLogController
                .buildTimesByTarget(activityLogPaths: activityLogs)
            return artifacts.map { artifact in
                if let buildTime = buildTimes[artifact.graphTarget.target.name] {
                    var metadata = artifact.metadata
                    metadata
                        .buildTime = buildTime /
                        1.5 // Divide by a factor to account for the additional time to build for multiple architectures or
                    // destinations.
                    var artifact = artifact
                    artifact.metadata = metadata
                    return artifact
                } else {
                    return artifact
                }
            }
        }

        private func copyDerivedDataArtifacts(
            into: AbsolutePath,
            productsDirectory: AbsolutePath,
            platform: Platform,
            binaryArtifactDirectories: inout [Platform: Set<AbsolutePath>]
        ) async throws {
            for artifact in try await fileSystem.glob(directory: productsDirectory, include: ["*"]).collect() {
                try fileHandler.copy(
                    from: artifact,
                    to: into.appending(component: artifact.basename)
                )
            }

            var platformDirectories = binaryArtifactDirectories[platform, default: Set()]
            platformDirectories.insert(into)
            binaryArtifactDirectories[platform] = platformDirectories
        }

        private func store(
            _ artifacts: [CacheGraphTargetBuiltArtifact],
            cacheStorage: CacheStoring,
            temporaryDirectory: AbsolutePath
        ) async throws -> [CacheStorableTarget] {
            try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Metadatas"))
            let storableTargets = Dictionary(
                uniqueKeysWithValues: try await artifacts
                    .reduce(into: [CacheStorableTarget: [AbsolutePath]]()) { acc, next in
                        acc[CacheStorableTarget(target: next.graphTarget, hash: next.hash, time: next.metadata.buildTime)] =
                            [next.path]
                    }.concurrentMap { storableTarget, paths in
                        let metadataFilePath = temporaryDirectory.appending(
                            components: "Metadatas",
                            "\(storableTarget.name)-\(storableTarget.hash)",
                            "Metadata.plist"
                        )
                        let metadata = CacheStorableItemMetadata(time: storableTarget.time)
                        try await fileSystem.makeDirectory(at: metadataFilePath.parentDirectory)
                        try await fileSystem.writeAsPlist(metadata, at: metadataFilePath)
                        var paths = paths
                        paths.append(metadataFilePath)
                        return (storableTarget, paths)
                    }
            )

            return try await cacheStorage.store(storableTargets, cacheCategory: .binaries)
        }

        private func cacheableTargets(
            for graph: Graph,
            configuration: String,
            config: Tuist,
            includedTargets: Set<String>,
            externalOnly: Bool,
            cacheStorage: CacheStoring
        ) async throws -> [(GraphTarget, String)] {
            let graphTraverser = GraphTraverser(graph: graph)
            let includedTargets = includedTargets
                .isEmpty ? Set(graphTraverser.allInternalTargets().map(\.target.name)) : includedTargets

            // When `externalOnly` is true, there is no need to compute `includedTargets` hashes
            let excludedTargets = externalOnly ? includedTargets : []
            let hashesByCacheableTarget = try await cacheGraphContentHasher.contentHashes(
                for: graph,
                configuration: configuration,
                defaultConfiguration: config.project.generatedProject?.generationOptions.defaultConfiguration,
                excludedTargets: excludedTargets,
                destination: nil
            )

            let sortedCacheableTargets = try graphTraverser.allTargetsTopologicalSorted()

            let cacheableTargets = sortedCacheableTargets.reduce(into: Set<CacheStorableTarget>()) { acc, next in
                if let targetContentHash = hashesByCacheableTarget[next] {
                    acc.formUnion([CacheStorableTarget(target: next, hash: targetContentHash.hash)])
                }
            }

            let cacheItems = try await cacheStorage.fetch(
                Set(hashesByCacheableTarget.map { CacheStorableItem(name: $0.key.target.name, hash: $0.value.hash) }),
                cacheCategory: .binaries
            )

            await RunMetadataStorage.current.update(
                binaryCacheItems: hashesByCacheableTarget.reduce(into: [:]) { result, element in
                    let cacheItem = cacheItems.keys.first(where: { $0.hash == element.value.hash }) ?? CacheItem(
                        name: element.key.target.name,
                        hash: element.value.hash,
                        source: .miss,
                        cacheCategory: .binaries
                    )
                    result[element.key.path, default: [:]][element.key.target.name] = cacheItem
                }
            )

            await RunMetadataStorage.current.update(
                targetContentHashSubhashes: hashesByCacheableTarget.reduce(into: [:]) { result, element in
                    result[element.value.hash] = element.value.subhashes
                }
            )

            let existingTargetHashes = Set(
                cacheItems.map(\.key.hash)
            )

            return cacheableTargets.compactMap {
                existingTargetHashes.contains($0.hash) ? nil : ($0.target, $0.hash)
            }
        }
    }
#endif
