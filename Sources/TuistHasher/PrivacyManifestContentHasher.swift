import Foundation
import Path
import TuistCore
import XcodeGraph

public protocol PrivacyManifestContentHashing {
    func hash(_ privacyManifest: PrivacyManifest) throws -> String
}

public final class PrivacyManifestContentHasher: PrivacyManifestContentHashing {
    private let contentHasher: ContentHashing

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func hash(_ privacyManifest: PrivacyManifest) throws -> String {
        var hashes: [String] = []

        hashes.append(try contentHasher.hash(privacyManifest.tracking ? "1" : "0"))
        hashes.append(try contentHasher.hash(privacyManifest.trackingDomains))
        hashes.append(try contentHasher.hash(privacyManifest.collectedDataTypes.asJSONString()))
        hashes.append(try contentHasher.hash(privacyManifest.accessedApiTypes.asJSONString()))

        return try contentHasher.hash(hashes)
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
