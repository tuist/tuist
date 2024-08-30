import Foundation
import TuistCore
import XcodeGraph

public protocol ResourcesContentHashing {
    func hash(identifier: String, resources: ResourceFileElements) throws -> MerkleNode
}

/// `ResourcesContentHasher`
/// is responsible for computing a unique hash that identifies a list of resources
public final class ResourcesContentHasher: ResourcesContentHashing {
    private let contentHasher: ContentHashing
    private let privacyManifestContentHasher: PrivacyManifestContentHasher
    private let platformConditionContentHasher: PlatformConditionContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        self.init(
            contentHasher: contentHasher,
            privacyManifestContentHasher: PrivacyManifestContentHasher(contentHasher: contentHasher),
            platformConditionContentHasher: PlatformConditionContentHasher(contentHasher: contentHasher)
        )
    }

    public init(
        contentHasher: ContentHashing,
        privacyManifestContentHasher: PrivacyManifestContentHasher,
        platformConditionContentHasher: PlatformConditionContentHashing
    ) {
        self.contentHasher = contentHasher
        self.privacyManifestContentHasher = privacyManifestContentHasher
        self.platformConditionContentHasher = platformConditionContentHasher
    }

    // MARK: - ResourcesContentHashing

    public func hash(identifier: String, resources: ResourceFileElements) throws -> MerkleNode {
        var children: [MerkleNode] = try resources.resources
            .sorted(by: { $0.path < $1.path })
            .map { try hashResourceFileElement(element: $0) }

        if let privacyManifest = resources.privacyManifest {
            children.append(try privacyManifestContentHasher.hash(
                identifier: "privacyManifest",
                privacyManifest: privacyManifest
            ))
        }

        return MerkleNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: identifier,
            children: children
        )
    }

    private func hashResourceFileElement(element: ResourceFileElement) throws -> MerkleNode {
        var children: [MerkleNode] = [
            MerkleNode(hash: try contentHasher.hash(path: element.path), identifier: "content"),
            MerkleNode(hash: try contentHasher.hash(element.isReference), identifier: "isReference"),
            MerkleNode(hash: try contentHasher.hash(element.tags), identifier: "tags"),
        ]

        if let inclusionCondition = element.inclusionCondition {
            children.append(try platformConditionContentHasher.hash(
                identifier: "inclusionCondition",
                platformCondition: inclusionCondition
            ))
        }

        return MerkleNode(
            hash: try contentHasher.hash(children.map(\.hash)),
            identifier: element.path.pathString,
            children: children
        )
    }
}
