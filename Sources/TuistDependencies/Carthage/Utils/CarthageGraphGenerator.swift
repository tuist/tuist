import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

/// A protocol that defines an interface to generate the `DependenciesGraph` for the `Carthage` dependencies.
public protocol CarthageGraphGenerating {
    /// Generates the `DependenciesGraph` for the `Carthage` dependencies.
    /// - Parameter path: The path to the directory that contains the `Carthage/Build` directory where `Carthage` installed dependencies.
    /// - Parameter platforms: A list of platforms to generate for
    func generate(at path: AbsolutePath, for platforms: Set<TuistGraph.Platform>?) throws -> TuistCore.DependenciesGraph
}

public final class CarthageGraphGenerator: CarthageGraphGenerating {
    public init() {}

    public func generate(at path: AbsolutePath, for platforms: Set<TuistGraph.Platform>?) throws -> TuistCore.DependenciesGraph {
        let versionFilePaths = try FileHandler.shared
            .contentsOfDirectory(path)
            .filter { $0.extension == "version" }

        let jsonDecoder = JSONDecoder()
        let products = try versionFilePaths
            .map { try FileHandler.shared.readFile($0) }
            .map { try jsonDecoder.decode(CarthageVersionFile.self, from: $0) }
            .flatMap { $0.allProducts }

        let externalDependencies: [String: [ProjectDescription.TargetDependency]] = Dictionary(grouping: products, by: \.name)
            .compactMapValues { products in
                guard let product = products.first else { return nil }

                var pathString = ""
                pathString += Constants.tuistDirectoryName
                pathString += "/"
                pathString += Constants.DependenciesDirectory.name
                pathString += "/"
                pathString += Constants.DependenciesDirectory.carthageDirectoryName
                pathString += "/"

                if let xcFrameworkName = product.container {
                    pathString += xcFrameworkName
                    return [.xcframework(path: Path(pathString))]
                }

                if let platforms = platforms {
                    let paths = platforms.map { $0.carthageDirectory }
                    let frameworks = paths.map { path -> ProjectDescription.TargetDependency in
                        pathString += path
                        pathString += "/"
                        pathString += product.name
                        pathString += ".framework"
                        return .framework(path: Path(pathString))
                    }
                    return frameworks
                }

                logger.warning("\(product.name) was not added to the DependenciesGraph", metadata: .subsection)
                return nil
            }

        return DependenciesGraph(externalDependencies: externalDependencies, externalProjects: [:])
    }
}
