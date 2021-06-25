import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

/// A protocol that defines an interface to generate the `DependenciesGraph` for the `Carthage` dependencies.
public protocol CarthageGraphGenerating {
    /// Generates the `DependenciesGraph` for the `Carthage` dependencies.
    /// - Parameter path: The path to the directory that contains the `Carthage/Build` directory where `Carthage` installed dependencies.
    func generate(at path: AbsolutePath) throws -> DependenciesGraph
}

public final class CarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    public func generate(at path: AbsolutePath) throws -> DependenciesGraph {
        let versionFilePaths = try FileHandler.shared
            .contentsOfDirectory(path)
            .filter { $0.extension == "version" }

        let jsonDecoder = JSONDecoder()
        let products = try versionFilePaths
            .map { try FileHandler.shared.readFile($0) }
            .map { try jsonDecoder.decode(CarthageVersionFile.self, from: $0) }
            .flatMap { $0.allProducts }

        let thirdPartyDependencies: [String: ThirdPartyDependency] = Dictionary(grouping: products, by: \.name)
            .compactMapValues { product in
                guard let frameworkName = product.first?.container else { return nil }

                let path = AbsolutePath("/")
                    .appending(components: [
                        Constants.tuistDirectoryName,
                        Constants.DependenciesDirectory.name,
                        Constants.DependenciesDirectory.carthageDirectoryName,
                        frameworkName,
                    ])

                return .xcframework(path: path)
            }

        return DependenciesGraph(thirdPartyDependencies: thirdPartyDependencies)
    }
}
