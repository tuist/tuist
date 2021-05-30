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
        let versionFiles = try versionFilePaths
            .map { try fileHandler.readFile($0) }
            .map { try jsonDecoder.decode(CarthageVersionFile.self, from: $0) }
        
//        logger.info("\(path)")
//        logger.info("\(versionFilePaths)")
//        logger.info("\(versionFiles)")
        
        #warning("laxmorek: WIP version, refactor me!")
        let nodes = versionFiles
            .reduce(into: [String: DependenciesGraphNode]()) { result, versionFile in
                versionFile.iOS
                    .forEach {
                        result[$0.name] = .xcframework(path: AbsolutePath("/" +  $0.container))
                    }
                versionFile.tvOS
                    .forEach {
                        result[$0.name] = .xcframework(path: AbsolutePath("/" +  $0.container))
                    }
                versionFile.macOS
                    .forEach {
                        result[$0.name] = .xcframework(path: AbsolutePath("/" +  $0.container))
                    }
                versionFile.watchOS
                    .forEach {
                        result[$0.name] = .xcframework(path: AbsolutePath("/" +  $0.container))
                    }
            }
        
        return DependenciesGraph(nodes: nodes)
    }
}
