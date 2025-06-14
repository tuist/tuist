import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol SourceFilesContentHashing {
    func hash(identifier: String, sources: [SourceFile]) async throws -> MerkleNode
}

/// `SourceFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of source files, considering their content
public final class SourceFilesContentHasher: SourceFilesContentHashing {
    private let contentHasher: ContentHashing
    private let platformConditionContentHasher: PlatformConditionContentHashing

    // MARK: - Init

    public init(
        contentHasher: ContentHashing,
        platformConditionContentHasher: PlatformConditionContentHashing
    ) {
        self.contentHasher = contentHasher
        self.platformConditionContentHasher = platformConditionContentHasher
    }

    // MARK: - SourceFilesContentHashing

    /// Returns a unique hash that identifies an arry of sourceFiles
    /// First it hashes the content of every file and append to every hash the compiler flags of the file. It assumes the files
    /// are always sorted the same way.
    /// Then it hashes again all partial hashes to get a unique identifier that represents a group of source files together with
    /// their compiler flags
    public func hash(identifier: String, sources: [SourceFile]) async throws -> MerkleNode {
        var children: [MerkleNode] = []

        for source in sources.sorted(by: { $0.path < $1.path }) {
            if let hash = source.contentHash {
                children.append(MerkleNode(
                    hash: hash,
                    identifier: source.path.pathString,
                    children: []
                ))
            } else {
                var sourceChildren: [MerkleNode] = []
                sourceChildren.append(MerkleNode(
                    hash: try await contentHasher.hash(path: source.path),
                    identifier: "content",
                    children: []
                ))

                if let compilerFlags = source.compilerFlags {
                    sourceChildren.append(MerkleNode(
                        hash: try contentHasher.hash(compilerFlags),
                        identifier: "compilerFlags",
                        children: []
                    ))
                }

                if let codeGen = source.codeGen {
                    sourceChildren.append(MerkleNode(
                        hash: try contentHasher.hash(codeGen.rawValue),
                        identifier: "codeGen",
                        children: []
                    ))
                }

                if let compilationCondition = source.compilationCondition {
                    sourceChildren.append(try platformConditionContentHasher.hash(
                        identifier: "compilationCondition",
                        platformCondition: compilationCondition
                    ))
                }

                children.append(MerkleNode(
                    hash: try contentHasher.hash(sourceChildren.map(\.hash)),
                    identifier: source.path.pathString,
                    children: sourceChildren
                ))
            }
        }

        return MerkleNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: identifier,
            children: children
        )
    }
}
