import Foundation
import TuistCore
import XcodeGraph

public protocol CoreDataModelsContentHashing {
    func hash(identifier: String, coreDataModels: [CoreDataModel]) throws -> MerkleNode
}

/// `CoreDataModelsContentHasher`
/// is responsible for computing a unique hash that identifies a list of CoreData models
public final class CoreDataModelsContentHasher: CoreDataModelsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CoreDataModelsContentHashing

    public func hash(identifier: String, coreDataModels: [CoreDataModel]) throws -> MerkleNode {
        let children = try coreDataModels.map { coreDataModel in
            /**
             Since the directory being hashed through the attribute "path" contains the rest of the attributes, we are implicitly hashing them
             and therefore it's not necessary to hash them.
             */
            return MerkleNode(
                hash: try contentHasher.hash(path: coreDataModel.path),
                identifier: coreDataModel.path.pathString
            )
        }

        return MerkleNode(
            hash: try contentHasher.hash(children),
            identifier: identifier,
            children: children
        )
    }
}
