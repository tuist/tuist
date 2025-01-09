import Foundation
import TuistCore
import XcodeGraph

public protocol PrivacyManifestContentHashing {
    func hash(identifier: String, privacyManifest: PrivacyManifest) throws -> MerkleNode
}

public final class PrivacyManifestContentHasher: PrivacyManifestContentHashing {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func hash(identifier: String, privacyManifest: PrivacyManifest) throws -> MerkleNode {
        var children: [MerkleNode] = []

        children.append(MerkleNode(hash: try contentHasher.hash(privacyManifest.tracking), identifier: "tracking"))
        children.append(MerkleNode(hash: try contentHasher.hash(privacyManifest.trackingDomains), identifier: "trackingDomains"))
        children.append(MerkleNode(
            hash: try contentHasher.hash(privacyManifest.collectedDataTypes.asJSONString()),
            identifier: "collectedDataTypes"
        ))
        children.append(MerkleNode(
            hash: try contentHasher.hash(privacyManifest.accessedApiTypes.asJSONString()),
            identifier: "accessedApiTypes"
        ))

        return MerkleNode(hash: try contentHasher.hash(children.map(\.hash)), identifier: identifier, children: children)
    }
}

extension [[String: Plist.Value]] {
    fileprivate func asJSONString() throws -> String {
        let normalized = map { dictionary in
            dictionary.mapValues { $0.normalize() }
        }
        return String(data: try JSONSerialization.data(withJSONObject: normalized, options: .sortedKeys), encoding: .utf8)!
    }
}
