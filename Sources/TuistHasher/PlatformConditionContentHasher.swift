import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
public protocol PlatformConditionContentHashing {
    func hash(identifier: String, platformCondition: PlatformCondition) throws -> MerkelNode
}

public struct PlatformConditionContentHasher: PlatformConditionContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func hash(identifier: String, platformCondition: PlatformCondition) throws -> MerkelNode {
        var children: [MerkelNode] = []

        try platformCondition.platformFilters.sorted().forEach { filter in
            children.append(MerkelNode(
                hash: try contentHasher.hash(filter.xcodeprojValue),
                identifier: filter.xcodeprojValue,
                children: []
            ))
        }

        return MerkelNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: identifier,
            children: children
        )
    }
}
