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
    private let fileHandler: FileHandling
    
    public init(
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.fileHandler = fileHandler
    }
    
    public func generate(at path: AbsolutePath) throws -> DependenciesGraph {
        let versionFilePaths = try fileHandler
            .contentsOfDirectory(path)
            .filter { $0.extension == "version" }
        
        let jsonDecoder = JSONDecoder()
        let products = try versionFilePaths
            .map { try fileHandler.readFile($0) }
            .map { try jsonDecoder.decode(CarthageVersionFile.self, from: $0) }
            .flatMap { $0.allProducts }
        
        let nodes = Dictionary(grouping: products, by: { $0.name })
            .reduce(into: [String: DependenciesGraphNode]()) { result, next in
                guard let frameworkName = next.value.first?.container else { return }
                
                let path = AbsolutePath("/")
                    .appending(component: Constants.tuistDirectoryName)
                    .appending(component: Constants.DependenciesDirectory.name)
                    .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
                    .appending(component: frameworkName)
                
                let architectures: Set<BinaryArchitecture> = Set(next.value.flatMap { $0.architectures })
                result[next.key] = .xcframework(path: path, architectures: architectures)
            }
        
        return DependenciesGraph(nodes: nodes)
    }
}
