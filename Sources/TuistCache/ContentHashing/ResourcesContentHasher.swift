import Foundation
import TuistCore
import TuistGraph
import TSCBasic

public protocol ResourcesContentHashing {
    func hash(resources: [FileElement], sourceRootPath: AbsolutePath) throws -> String
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

    public func hash(resources: [FileElement], sourceRootPath: AbsolutePath) throws -> String {
        let hashes = try resources
            .sorted { $0.path.pathString < $1.path.pathString }
            .map {
                try contentHasher.hash($0.path.relative(to: sourceRootPath).pathString)
                    + ":"
                    + contentHasher.hash(path: $0.path)
            }

        return try contentHasher.hash(hashes)
    }
}
