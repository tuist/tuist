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
        let hashableTargets = graph.targets.filter { $0.target.product == .framework }
        let hashes = try hashableTargets.map { try makeContentHash(of: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    private func makeContentHash(of targetNode: TargetNode) throws -> String {
        // TODO: extend function to consider build settings, compiler flags, dependencies, and a lot more
        let sourcesHash = try hashSources(of: targetNode)
        let productHash = try hash(string: targetNode.target.productName)
        let platformHash = try hash(string: targetNode.target.platform.rawValue)
        return try hash(strings: [sourcesHash, productHash, platformHash])
    }

    private func hashSources(of targetNode: TargetNode) throws -> String {
        let hashes = try targetNode.target.sources.sorted(by: { $0.path < $1.path }).map(md5)
        let joinedHash = try hash(strings: hashes)
        return joinedHash
    }

    private func hash(string: String) throws -> String {
        guard let hash = string.checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(string)
        }
        return hash
    }

    private func hash(strings: [String]) throws -> String {
        guard let joinedHash = strings.joined().checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(strings.joined())
        }
        return joinedHash
    }

    private func md5(of source: Target.SourceFile) throws -> String {
        guard let sourceData = try? fileHandler.readFile(source.path) else {
            throw ContentHashingError.fileNotFound(source.path)
        }
        guard let hash = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(source.path)
        }
        return hash
    }
}
