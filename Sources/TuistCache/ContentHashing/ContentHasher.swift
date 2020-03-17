import Foundation
import Basic
import TuistCore
import TuistSupport

public protocol ContentHashing {
    func hash(_ string: String) throws -> String
    func hash(_ strings: Array<String>) throws -> String
    func hash(_ filePath: AbsolutePath) throws -> String
}

/// ContentHasher
/// The single source of truth for hashing content
/// Using md5 checksum to uniquely hash strings and data

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

    public func hash(_ strings: Array<String>) throws -> String {
        return try hash(strings.joined())
    }

    public func hash(_ filePath: AbsolutePath) throws -> String {
        guard let sourceData = try? fileHandler.readFile(filePath) else {
            throw ContentHashingError.fileNotFound(filePath)
        }
        guard let hash = sourceData.checksum(algorithm: .md5) else {
            throw ContentHashingError.fileHashingFailed(filePath)
        }
        return hash
    }
}
