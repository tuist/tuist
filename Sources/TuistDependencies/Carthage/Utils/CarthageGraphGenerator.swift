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

        let thirdPartyDependencies = Dictionary(grouping: products, by: { $0.name })
            .reduce(into: [String: ThirdPartyDependency]()) { result, product in
                guard let frameworkName = product.value.first?.container else { return }

                let path = AbsolutePath("/")
                    .appending(components: [
                        Constants.tuistDirectoryName,
                        Constants.DependenciesDirectory.name,
                        Constants.DependenciesDirectory.carthageDirectoryName,
                        frameworkName,
                    ])

                let architectures: Set<BinaryArchitecture> = Set(product.value.flatMap { $0.architectures })
                result[product.key] = .xcframework(path: path, architectures: architectures)
            }

        return DependenciesGraph(thirdPartyDependencies: thirdPartyDependencies)
    }
}
