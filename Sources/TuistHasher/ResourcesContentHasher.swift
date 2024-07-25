import Foundation
import TuistCore
import XcodeGraph

public protocol ResourcesContentHashing {
    func hash(resources: ResourceFileElements) throws -> String
}

/// `ResourcesContentHasher`
/// is responsible for computing a unique hash that identifies a list of resources
public final class ResourcesContentHasher: ResourcesContentHashing {
    private let contentHasher: ContentHashing
    private let privacyManifestContentHasher: PrivacyManifestContentHasher

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        self.init(
            contentHasher: contentHasher,
            privacyManifestContentHasher: PrivacyManifestContentHasher(contentHasher: contentHasher)
        )
    }

    public init(
        contentHasher: ContentHashing,
        privacyManifestContentHasher: PrivacyManifestContentHasher
    ) {
        self.contentHasher = contentHasher
        self.privacyManifestContentHasher = privacyManifestContentHasher
    }

    // MARK: - ResourcesContentHashing

    public func hash(resources: ResourceFileElements) throws -> String {
        var hashes = try resources.resources
            .sorted(by: { $0.path < $1.path })
            .map { try contentHasher.hash(path: $0.path) }

        if let privacyManifest = resources.privacyManifest {
            hashes.append(try privacyManifestContentHasher.hash(privacyManifest))
        }

        return try contentHasher.hash(hashes)
    }
}
