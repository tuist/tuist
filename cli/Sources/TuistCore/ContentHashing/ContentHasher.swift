import CryptoKit
import FileSystem
import Foundation
import Path

/// `ContentHasher`
/// is the single source of truth for hashing content.
/// It uses md5 checksum to uniquely hash strings and data
/// Consider using CacheContentHasher to avoid computing the same hash twice
public struct ContentHasher: ContentHashing {
    private let fileSystem: FileSysteming
    private let filesFilter = HashingFilesFilter()

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - ContentHashing

    public func hash(_ data: Data) -> String {
        Insecure.MD5.hash(data: data)
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    public func hash(_ boolean: Bool) throws -> String {
        return try hash(boolean ? "1" : "0")
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
        let dictString = dictionary.keys.sorted()
            .map { "\($0):\(dictionary[$0]!)" }
            .joined(separator: "-")
        return try hash(dictString)
    }

    public func hash(path filePath: AbsolutePath) async throws -> String {
        if try await fileSystem.exists(filePath, isDirectory: true) {
            return try await fileSystem.glob(directory: filePath, include: ["*"])
                .collect()
                .filter { filesFilter($0) }
                .concurrentMap { filePath -> String? in
                    guard try await fileSystem.exists(filePath) else { return nil }
                    let filePath = try await fileSystem.resolveSymbolicLink(filePath)
                    return try await hash(path: filePath)
                }
                .compactMap { $0 }
                .sorted()
                .joined(separator: "-")
        }

        guard try await fileSystem.exists(filePath) else {
            throw ContentHashingError.fileHashingFailed(filePath)
        }
        guard let sourceData = try? await fileSystem.readFile(at: filePath) else {
            throw ContentHashingError.failedToReadFile(filePath)
        }

        return hash(sourceData)
    }
}
