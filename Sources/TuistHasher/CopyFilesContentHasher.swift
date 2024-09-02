import Foundation
import TuistCore
import XcodeGraph

public protocol CopyFilesContentHashing {
    func hash(identifier: String, copyFiles: [CopyFilesAction]) throws -> MerkleNode
}

/// `CopyFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of CopyFilesAction models
public final class CopyFilesContentHasher: CopyFilesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CopyFilesContentHashing

    public func hash(identifier: String, copyFiles: [CopyFilesAction]) throws -> MerkleNode {
        let children = copyFiles.map { _ in
            return MerkleNode(hash: "xxx", identifier: "uuu", children: [])
        }
        return MerkleNode(
            hash: try contentHasher.hash(children),

            identifier: identifier,
            children: children
        )
    }
}
