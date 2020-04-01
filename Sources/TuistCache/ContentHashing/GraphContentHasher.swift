import Checksum
import Foundation
import TuistCore
import TuistSupport

public protocol GraphContentHashing {
    func contentHashes(for graph: Graph) throws -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    public func contentHashes(for graph: Graph) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        
        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
            targets.compactMap { target in
                if self.isCacheable(target, visited: &visitedNodes) { return target }
                return nil
            }
        }
        let hashes = try hashableTargets.map { try makeContentHash(of: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }
    
    fileprivate func isCacheable(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        
        let isFramework = target.target.product == .framework
        let noXCTestDependency = target.sdkDependencies.first(where: { $0.name == "XCTest.framework" }) == nil
        let allTargetDependenciesAreHasheable = target.targetDependencies.allSatisfy({ isCacheable($0, visited: &visited) })
        
        let cacheable = isFramework && noXCTestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }

    fileprivate func makeContentHash(of targetNode: TargetNode) throws -> String {
        // TODO: extend function to consider build settings, compiler flags, dependencies, and a lot more
        let sourcesHash = try hashSources(of: targetNode)
        let productHash = try hash(string: targetNode.target.productName)
        let platformHash = try hash(string: targetNode.target.platform.rawValue)
        return try hash(strings: [sourcesHash, productHash, platformHash])
    }

    fileprivate func hashSources(of targetNode: TargetNode) throws -> String {
        let hashes = try targetNode.target.sources.sorted(by: { $0.path < $1.path }).map(md5)
        let joinedHash = try hash(strings: hashes)
        return joinedHash
    }

    fileprivate func hash(string: String) throws -> String {
        guard let hash = string.checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(string)
        }
        return hash
    }

    fileprivate func hash(strings: [String]) throws -> String {
        guard let joinedHash = strings.joined().checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(strings.joined())
        }
        return joinedHash
    }

    fileprivate func md5(of source: Target.SourceFile) throws -> String {
        guard let sourceData = try? fileHandler.readFile(source.path) else {
            throw ContentHashingError.fileNotFound(source.path)
        }
        guard let hash = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(source.path)
        }
        return hash
    }
}
