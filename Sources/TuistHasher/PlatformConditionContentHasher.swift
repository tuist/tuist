import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
public protocol PlatformConditionContentHashing {
    func hash(identifier: String, platformCondition: PlatformCondition) throws -> MerkleNode
}

public struct PlatformConditionContentHasher: PlatformConditionContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func hash(identifier: String, platformCondition: PlatformCondition) throws -> MerkleNode {
        var children: [MerkleNode] = []

        try platformCondition.platformFilters.sorted().forEach { filter in
            children.append(MerkleNode(
                hash: try contentHasher.hash(filter.xcodeprojValue),
                identifier: filter.xcodeprojValue,
                children: []
            ))
        }

        return MerkleNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: identifier,
            children: children
        )
    }
}
