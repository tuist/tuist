import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol FileContentHashing {
    func hash(fileAtPath: AbsolutePath) throws -> String
}

public protocol ContentHashing: FileContentHashing {
    func hash(_ string: String) throws -> String
    func hash(_ strings: [String]) throws -> String
}

/// `ContentHasher`
/// is the single source of truth for hashing content.
/// It uses md5 checksum to uniquely hash strings and data
/// Consider using CacheContentHasher to avoid computing the same hash twice
public final class ContentHasher: ContentHashing {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    // MARK: - ContentHashing

    public func hash(_ string: String) throws -> String {
        guard let hash = string.checksum(algorithm: .md5) else {
            throw ContentHashingError.stringHashingFailed(string)
        }
        return hash
    }

    public func hash(_ strings: [String]) throws -> String {
        try hash(strings.joined())
    }

    public func hash(fileAtPath filePath: AbsolutePath) throws -> String {
        guard fileHandler.exists(filePath) else {
            throw FileHandlerError.fileNotFound(filePath)
        }
        guard let sourceData = try? fileHandler.readFile(filePath) else {
            throw ContentHashingError.failedToReadFile(filePath)
        }
        guard let hash = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(filePath)
        }
        return hash
    }
}
