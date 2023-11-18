import CryptoKit
import Foundation
import TSCBasic
import TuistSupport

/// `ContentHasher`
/// is the single source of truth for hashing content.
/// It uses md5 checksum to uniquely hash strings and data
/// Consider using CacheContentHasher to avoid computing the same hash twice
public final class ContentHasher: ContentHashing {
    private let fileHandler: FileHandling
    private let filesFilter = HashingFilesFilter()

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }

    // MARK: - ContentHashing

    public func hash(_ data: Data) -> String {
        Insecure.MD5.hash(data: data)
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    public func hash(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else {
            throw ContentHashingError.stringHashingFailed(string)
        }
        return hash(data)
    }

    public func hash(_ strings: [String]) throws -> String {
        try hash(strings.joined())
    }

    public func hash(_ dictionary: [String: String]) throws -> String {
        let sortedKeys = dictionary.keys.sorted { $0 < $1 }
        var dictString = ""
        for (counter, key) in sortedKeys.enumerated() {
            let value: String = dictionary[key]!
            dictString += "\(key):\(value)"
            let isLastKey = counter == (sortedKeys.count - 1)
            if !isLastKey {
                dictString += "-"
            }
        }
        return try hash(dictString)
    }

    public func hash(path filePath: AbsolutePath) throws -> String {
        if fileHandler.isFolder(filePath) {
            return try fileHandler.contentsOfDirectory(filePath)
                .filter { filesFilter($0) }
                .sorted(by: { $0 < $1 })
                .map { try hash(path: $0) }
                .joined(separator: "-")
        }

        guard fileHandler.exists(filePath) else {
            throw FileHandlerError.fileNotFound(filePath)
        }
        guard let sourceData = try? fileHandler.readFile(filePath) else {
            throw ContentHashingError.failedToReadFile(filePath)
        }

        return hash(sourceData)
    }
}
