import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
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

        let externalDependencies: [String: [TargetDependency]] = Dictionary(grouping: products, by: \.name)
            .compactMapValues { products in
                guard let product = products.first else { return nil }

                guard let xcFrameworkName = product.container else {
                    logger.warning("\(product.name) was not added to the DependenciesGraph", metadata: .subsection)
                    return nil
                }

                let path = AbsolutePath("/")
                    .appending(components: [
                        Constants.tuistDirectoryName,
                        Constants.DependenciesDirectory.name,
                        Constants.DependenciesDirectory.carthageDirectoryName,
                        xcFrameworkName,
                    ])

                return [.xcframework(path: Path(path.pathString))]
            }

        return DependenciesGraph(externalDependencies: externalDependencies, externalProjects: [:])
    }
}
