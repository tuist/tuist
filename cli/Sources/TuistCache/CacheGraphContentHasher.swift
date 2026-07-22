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
        destination: SimulatorDeviceAndRuntime?
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

    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
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
        destination: SimulatorDeviceAndRuntime?
    ) async throws -> [GraphTarget: TargetContentHash] {
        let configuration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: defaultConfiguration,
            graph: graph
        )
        let hashingGraph = graphByScopingSettings(in: graph, to: configuration)

        if let exportHashedGraphPath = Environment.current.variables["TUIST_EXPORT_HASHED_GRAPH_PATH"],
           let exportPath = try? AbsolutePath(validating: exportHashedGraphPath)
        {
            try await fileSystem.writeAsJSON(hashingGraph, at: exportPath)
            Logger.current.debug("Graph used for hashing exported to \(exportPath.pathString)")
        }

        let version = versionFetcher.version()
        let hashes = try await graphContentHasher.contentHashes(
            for: hashingGraph,
            include: {
                isGraphTargetHashable(
                    $0,
                    excludedTargets: excludedTargets
                )
            },
            destination: destination,
            additionalStrings: [
                configuration,
                try await SwiftVersionProvider.current.swiftlangVersion(),
                version.rawValue,
            ]
        )

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
