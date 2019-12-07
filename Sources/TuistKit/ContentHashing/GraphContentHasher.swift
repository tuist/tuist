import Foundation
import TuistCore
import Checksum
import TuistSupport
import TuistCore

public protocol GraphContentHashing {
    func contentHashes(for graph: Graphing) throws -> Dictionary<TargetNode, String>
}

public final class GraphContentHasher: GraphContentHashing {
    private let fileHandler: FileHandling
    
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    public func contentHashes(for graph: Graphing) throws -> Dictionary<TargetNode, String> {
        let hashableTargets = graph.targets.filter { $0.target.product == .framework }
        let hashes = try hashableTargets.map { try makeContentHash(of: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }
    
    private func makeContentHash(of targetNode: TargetNode) throws -> String {
        return try hashSources(of: targetNode)
        //TODO: extend function to consider build settings, compiler flags, dependencies, and a lot more
    }
    
    private func hashSources(of targetNode: TargetNode) throws -> String {
        let hashes = try targetNode.target.sources.map(md5)
        guard let joinedHash = hashes.joined().checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(hashes.joined())
        }
        return joinedHash
    }
    
    private func md5(of source: Target.SourceFile) throws -> String{
        guard let sourceData = try? fileHandler.readFile(source.path) else {
            throw ContentHashingError.fileNotFound(source.path)
        }
        guard let checksum = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(source.path)
        }
        return checksum
    }
}
