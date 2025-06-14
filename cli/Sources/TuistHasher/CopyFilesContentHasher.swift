import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol CopyFilesContentHashing {
    func hash(identifier: String, copyFiles: [CopyFilesAction]) async throws -> MerkleNode
}

/// `CopyFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of CopyFilesAction models
public struct CopyFilesContentHasher: CopyFilesContentHashing {
    private let contentHasher: ContentHashing
    private let platformConditionContentHasher: PlatformConditionContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing, platformConditionContentHasher: PlatformConditionContentHashing) {
        self.contentHasher = contentHasher
        self.platformConditionContentHasher = platformConditionContentHasher
    }

    // MARK: - CopyFilesContentHashing

    public func hash(identifier: String, copyFiles: [CopyFilesAction]) async throws -> MerkleNode {
        let children = try await copyFiles.concurrentMap { action in
            var actionChildren: [MerkleNode] = [
                MerkleNode(hash: try contentHasher.hash(action.name), identifier: "name"),
                MerkleNode(hash: try contentHasher.hash(action.destination.rawValue), identifier: "destination"),
            ]
            let actionFiles = try await action.files.sorted(by: { $0.path < $1.path }).concurrentMap { file in
                var fileChildren: [MerkleNode] = [
                    MerkleNode(hash: try await contentHasher.hash(path: file.path), identifier: "content"),
                    MerkleNode(hash: try contentHasher.hash(file.isReference), identifier: "isReference"),
                    MerkleNode(hash: try contentHasher.hash(file.codeSignOnCopy), identifier: "codeSignOnCopy"),
                ]
                if let condition = file.condition {
                    fileChildren.append(try platformConditionContentHasher.hash(
                        identifier: "condition",
                        platformCondition: condition
                    ))
                }
                return MerkleNode(
                    hash: try contentHasher.hash(fileChildren),
                    identifier: file.path.pathString,
                    children: fileChildren
                )
            }
            actionChildren.append(MerkleNode(
                hash: try contentHasher.hash(actionFiles),
                identifier: "files",
                children: actionFiles
            ))

            if let subpath = action.subpath {
                actionChildren.append(MerkleNode(hash: try contentHasher.hash(subpath), identifier: "subpath"))
            }
            return MerkleNode(
                hash: try contentHasher.hash(actionChildren),
                identifier: action.name,
                children: actionChildren
            )
        }
        return MerkleNode(
            hash: try contentHasher.hash(children),

            identifier: identifier,
            children: children
        )
    }
}
