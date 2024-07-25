import Foundation
import Mockable
import Path
import TuistCore
import TuistHasher
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheGraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - configuration: Configuration to hash.
    ///     - config: The `Config.swift` model
    ///     - excludedTargets: Targets to be excluded from hashes calculation
    func contentHashes(
        for graph: Graph,
        configuration: String?,
        config: TuistCore.Config,
        excludedTargets: Set<String>
    ) throws -> [GraphTarget: String]
}

public final class CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let contentHasher: ContentHashing
    private let versionFetcher: CacheVersionFetching
    private static let cachableProducts: Set<Product> = [.framework, .staticFramework, .bundle, .macro]
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let xcodeController: XcodeControlling
    private let swiftVersionProvider: SwiftVersionProviding

    public convenience init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher,
            versionFetcher: CacheVersionFetcher(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            xcodeController: XcodeController.shared,
            swiftVersionProvider: SwiftVersionProvider.shared
        )
    }

    init(
        graphContentHasher: GraphContentHashing,
        contentHasher: ContentHashing,
        versionFetcher: CacheVersionFetching,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        xcodeController: XcodeControlling,
        swiftVersionProvider: SwiftVersionProviding
    ) {
        self.graphContentHasher = graphContentHasher
        self.contentHasher = contentHasher
        self.versionFetcher = versionFetcher
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.xcodeController = xcodeController
        self.swiftVersionProvider = swiftVersionProvider
    }

    public func contentHashes(
        for graph: Graph,
        configuration: String?,
        config: TuistCore.Config,
        excludedTargets: Set<String>
    ) throws -> [GraphTarget: String] {
        let graphTraverser = GraphTraverser(graph: graph)
        let version = versionFetcher.version()
        let configuration = try defaultConfigurationFetcher.fetch(
            configuration: configuration,
            config: config,
            graph: graph
        )

        let hashes = try graphContentHasher.contentHashes(
            for: graph,
            include: {
                self.isGraphTargetHashable(
                    $0,
                    graphTraverser: graphTraverser,
                    excludedTargets: excludedTargets
                )
            },
            additionalStrings: [
                configuration,
                try swiftVersionProvider.swiftlangVersion(),
                version.rawValue,
                xcodeController.selectedVersion().xcodeStringValue,
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

        /** The second condition is to exclude the resources bundle associated to the given target name */
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
