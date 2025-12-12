import Mockable
import TuistCore
import TuistHasher
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

public final class CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let contentHasher: ContentHashing
    private let versionFetcher: CacheVersionFetching
    private static let cachableProducts: Set<Product> = [.framework, .staticFramework, .bundle, .macro]
    private let defaultConfigurationFetcher: DefaultConfigurationFetching

    public convenience init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher,
            versionFetcher: CacheVersionFetcher(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher()
        )
    }

    init(
        graphContentHasher: GraphContentHashing,
        contentHasher: ContentHashing,
        versionFetcher: CacheVersionFetching,
        defaultConfigurationFetcher: DefaultConfigurationFetching
    ) {
        self.graphContentHasher = graphContentHasher
        self.contentHasher = contentHasher
        self.versionFetcher = versionFetcher
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
    }

    public func contentHashes(
        for graph: Graph,
        configuration: String?,
        defaultConfiguration: String?,
        excludedTargets: Set<String>,
        destination: SimulatorDeviceAndRuntime?
    ) async throws -> [GraphTarget: TargetContentHash] {
        let graphTraverser = GraphTraverser(graph: graph)
        let version = versionFetcher.version()
        let configuration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            defaultConfiguration: defaultConfiguration,
            graph: graph
        )

        let hashes = try await graphContentHasher.contentHashes(
            for: graph,
            include: {
                self.isGraphTargetHashable(
                    $0,
                    graphTraverser: graphTraverser,
                    excludedTargets: excludedTargets
                )
            },
            destination: destination,
            additionalStrings: [
                configuration,
                try SwiftVersionProvider.current.swiftlangVersion(),
                version.rawValue,
            ]
        )

        return hashes
    }

    private func isGraphTargetHashable(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        excludedTargets: Set<String>
    ) -> Bool {
        let product = target.target.product
        let name = target.target.name

        // The second condition is to exclude the resources bundle associated to the given target name
        let isExcluded = excludedTargets.contains(name) || excludedTargets
            .contains(target.target.name.dropPrefix("\(target.project.name)_"))
        let dependsOnXCTest = graphTraverser.dependsOnXCTest(path: target.path, name: name)
        let isHashableProduct = CacheGraphContentHasher.cachableProducts.contains(product)

        return isHashableProduct && !isExcluded && !dependsOnXCTest
    }

    private func isMacro(_ target: GraphTarget, graphTraverser: GraphTraversing) -> Bool {
        !graphTraverser.directSwiftMacroExecutables(path: target.path, name: target.target.name).isEmpty
    }
}
