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
        let children = try platformCondition.platformFilters.sorted().map {
            MerkleNode(
                hash: try contentHasher.hash($0.xcodeprojValue),
                identifier: "\($0)"
            )
        }

        return MerkleNode(
            hash: try contentHasher.hash(children),
            identifier: identifier,
            children: children
        )
    }
}
