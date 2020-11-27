import Foundation
import TuistCore

public protocol CopyFilesContentHashing {
    func hash(copyFiles: [CopyFilesAction]) throws -> String
}

/// `CopyFilesContentHasher`
/// is responsible for computing a unique hash that identifies a list of CopyFilesAction models
public final class CopyFilesContentHasher: CopyFilesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - CopyFilesContentHashing

    public func hash(copyFiles: [CopyFilesAction]) throws -> String {
        var stringsToHash: [String] = []
        for action in copyFiles {
            let fileHashes = try action.files.map { try contentHasher.hash(path: $0.path) }
            stringsToHash.append(contentsOf: fileHashes + [action.name, action.subpath, "\(action.destination.rawValue)"])
        }
        return try contentHasher.hash(stringsToHash)
    }
}
