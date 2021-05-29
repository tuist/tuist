import Foundation
import TuistCore
import TuistGraph

public protocol ResourcesContentHashing {
    func hash(resources: [ResourceFileElement]) throws -> String
}

/// `ResourcesContentHasher`
/// is responsible for computing a unique hash that identifies a list of resources
public final class ResourcesContentHasher: ResourcesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - ResourcesContentHashing

    public func hash(resources: [ResourceFileElement]) throws -> String {
        let hashes = try resources
            .sorted(by: { $0.path < $1.path })
            .map { try contentHasher.hash(path: $0.path) }

        return try contentHasher.hash(hashes)
    }
}
