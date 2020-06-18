import Foundation
import TuistCore

public protocol ResourcesContentHashing {
    func hash(resources: [FileElement]) throws -> String
}

/// `ResourcesContentHasher`
/// is responsible for computing a unique hash that identifies a list of resources
public final class ResourcesContentHasher: ResourcesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    public func hash(resources: [FileElement]) throws -> String {
        let hashes = try resources.map { try contentHasher.hash(fileAtPath: $0.path) }
        return try contentHasher.hash(hashes)
    }
}
