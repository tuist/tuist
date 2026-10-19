import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistHasher
import TuistLogging
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheGraphContentHashing {
    func contentHashes(
        for graph: Graph,
        configuration: String?,
        defaultConfiguration: String?,
        excludedTargets: Set<String>,
        destination: SimulatorDeviceAndRuntime?,
        coverage: BinaryCacheCoverage
    ) async throws -> [GraphTarget: TargetContentHash]
}

public struct CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let contentHasher: ContentHashing
    private let versionFetcher: CacheVersionFetching
    private static let cachableProducts: Set<Product> = [
        .framework,
        .staticFramework,
        .staticLibrary,
        .dynamicLibrary,
        .bundle,
        .macro,
    ]
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let fileSystem: FileSysteming

    /// The dimension of the key of a repository-owned target when a run collects coverage: the binaries
    /// warmed with coverage sit beside the plain ones, and a run with coverage on never reads the latter.
    /// Remote packages keep the plain key, since coverage is never kept for code outside the repository.
    public static let coverageDimension = "coverage"

    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        let contentHasher = CachedContentHasher(contentHasher: contentHasher)
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher,
            versionFetcher: CacheVersionFetcher(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            fileSystem: FileSystem()
        )
    }

    init(
        graphContentHasher: GraphContentHashing,
        contentHasher: ContentHashing,
        versionFetcher: CacheVersionFetching,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.graphContentHasher = graphContentHasher
        self.contentHasher = contentHasher
        self.versionFetcher = versionFetcher
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.fileSystem = fileSystem
    }

    public func contentHashes(
        for graph: Graph,
        configuration: String?,
        defaultConfiguration: String?,
        excludedTargets: Set<String>,
        destination: SimulatorDeviceAndRuntime?,
        coverage: BinaryCacheCoverage
    ) async throws -> [GraphTarget: TargetContentHash] {
        // Hashes depend on the resolved configuration, never on whether it was named explicitly, came
        // from the manifest, or fell back to the first debug configuration. A cache filled by
        // `tuist cache --configuration X` has to stay readable by a run that resolves to X without the flag.
        let resolvedConfiguration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: defaultConfiguration,
            graph: graph
        )
        Logger.current.debug("Hashing targets against the configuration \(resolvedConfiguration)")

        let hashingGraph = graphByScopingSettings(in: graph, to: resolvedConfiguration)

        if let exportHashedGraphPath = Environment.current.variables["TUIST_EXPORT_HASHED_GRAPH_PATH"],
           let exportPath = try? AbsolutePath(validating: exportHashedGraphPath)
        {
            try await fileSystem.writeAsJSON(hashingGraph, at: exportPath)
            Logger.current.debug("Graph used for hashing exported to \(exportPath.pathString)")
        }

        let version = versionFetcher.version()
        // Xcode releases can ship the same compiler with different SDKs, and binaries built against one
        // SDK don't import under another, so the Xcode build is hashed next to the compiler version.
        let additionalStrings = [
            resolvedConfiguration,
            try await SwiftVersionProvider.current.swiftlangVersion(),
            try await XcodeController.current.selectedBuildVersion(),
            version.rawValue,
        ]
        let targetAdditionalStrings = targetAdditionalStrings(
            additionalStrings, coverage: coverage, configuration: resolvedConfiguration, graph: graph
        )
        var hashes = try await graphContentHasher.contentHashes(
            for: hashingGraph,
            include: {
                isGraphTargetHashable(
                    $0,
                    excludedTargets: excludedTargets
                )
            },
            destination: destination,
            additionalStrings: targetAdditionalStrings
        )

        if !Environment.current.isLegacyModuleCacheEnabled {
            let fingerprints = try await BinaryCacheFingerprintHasher(contentHasher: contentHasher).fingerprints(
                graph: hashingGraph, targets: Set(hashes.keys),
                additionalStrings: targetAdditionalStrings, targetHashes: hashes
            )
            for (target, values) in fingerprints {
                hashes[target]?.binaryCacheFingerprints = values
            }
        }

        return Dictionary(uniqueKeysWithValues: hashes.map { target, hash in
            guard let project = graph.projects[target.path],
                  let originalTarget = project.targets[target.target.name]
            else {
                return (target, hash)
            }
            return (
                GraphTarget(path: target.path, target: originalTarget, project: project),
                hash
            )
        })
    }

    private func graphByScopingSettings(in graph: Graph, to configuration: String) -> Graph {
        var hashingGraph = graph
        hashingGraph.projects = graph.projects.mapValues { project in
            guard let buildConfiguration = project.settings.configurations.keys
                .first(where: { $0.name.caseInsensitiveCompare(configuration) == .orderedSame })
            else {
                return project
            }

            var project = project
            project.settings = settings(project.settings, scopedTo: buildConfiguration)
            project.targets = project.targets.mapValues { target in
                guard let targetSettings = target.settings else { return target }
                var target = target
                target.settings = settings(targetSettings, scopedTo: buildConfiguration)
                return target
            }
            return project
        }
        return hashingGraph
    }

    /// Release configurations are never warmed with coverage, so their keys stay plain and a run with
    /// coverage on reads the plain binaries, as it did before the dimension existed.
    private func targetAdditionalStrings(
        _ additionalStrings: [String],
        coverage: BinaryCacheCoverage,
        configuration: String,
        graph: Graph
    ) -> (GraphTarget) -> [String] {
        let isDebug = graph.projects.values
            .flatMap(\.settings.configurations.keys)
            .first { $0.name.caseInsensitiveCompare(configuration) == .orderedSame }?
            .variant == .debug
        let instrumented = isDebug && coverage.isOn(in: graph)
        // A target without an external hash is keyed as the repository's code, the rule the server judges a
        // run's coverage by (`external_hash` empty). It also admits a package referenced by path from outside
        // the checkout and a local git clone, whose coverage the export drops; that only costs instrumentation.
        return { target in
            guard instrumented, target.project.externalHash == nil else { return additionalStrings }
            return additionalStrings + [Self.coverageDimension]
        }
    }

    private func settings(_ settings: Settings, scopedTo buildConfiguration: BuildConfiguration) -> Settings {
        Settings(
            base: settings.base,
            baseDebug: buildConfiguration.variant == .debug ? settings.baseDebug : [:],
            configurations: settings.configurations.filter { $0.key == buildConfiguration },
            defaultSettings: settings.defaultSettings,
            defaultConfiguration: settings.defaultConfiguration.flatMap {
                $0.caseInsensitiveCompare(buildConfiguration.name) == .orderedSame ? $0 : nil
            }
        )
    }

    private func isGraphTargetHashable(
        _ target: GraphTarget,
        excludedTargets: Set<String>
    ) -> Bool {
        let product = target.target.product
        let name = target.target.name

        // The second condition is to exclude the resources bundle associated to the given target name
        let isExcluded = excludedTargets.contains(name) || excludedTargets
            .contains(target.target.name.dropPrefix("\(target.project.name)_"))
        let isTestBundle = target.target.product.testsBundle
        let isHashableProduct = CacheGraphContentHasher.cachableProducts.contains(product)

        return isHashableProduct && !isExcluded && !isTestBundle
    }

    private func isMacro(_ target: GraphTarget, graphTraverser: GraphTraversing) -> Bool {
        !graphTraverser.directSwiftMacroExecutables(path: target.path, name: target.target.name).isEmpty
    }
}
