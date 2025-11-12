@preconcurrency import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

public enum KeyValueOperationType: String, Codable {
    case read
    case write
}

/// Protocol for storing and retrieving KeyValue metadata
@Mockable
public protocol KeyValueMetadataStoring: Sendable {
    /// Store metadata for a KeyValue operation identified by cache key
    func storeMetadata(_ metadata: KeyValueMetadata, for cacheKey: String, operationType: KeyValueOperationType) async throws

    /// Retrieve metadata for a KeyValue operation
    func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata?
}

public struct KeyValueMetadataStore: KeyValueMetadataStoring {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func storeMetadata(
        _ metadata: KeyValueMetadata,
        for cacheKey: String,
        operationType: KeyValueOperationType
    ) async throws {
        let keyValueDirectory = Environment.current.stateDirectory
            .appending(component: "keyvalue")
            .appending(component: operationType.rawValue)
        try await fileSystem.makeDirectory(at: keyValueDirectory)

        let sanitizedKey = sanitizeCacheKey(cacheKey)
        let metadataFilePath = keyValueDirectory.appending(component: "\(sanitizedKey).json")

        if try await fileSystem.exists(metadataFilePath) {
            try await fileSystem.remove(metadataFilePath)
        }

        try await fileSystem.writeAsJSON(metadata, at: metadataFilePath)
    }

    public func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata? {
        let keyValueDirectory = Environment.current.stateDirectory
            .appending(component: "keyvalue")
            .appending(component: operationType.rawValue)
        let sanitizedKey = sanitizeCacheKey(cacheKey)
        let metadataFilePath = keyValueDirectory.appending(component: "\(sanitizedKey).json")

        guard try await fileSystem.exists(metadataFilePath) else {
            return nil
        }

        return try await fileSystem.readJSONFile(at: metadataFilePath)
    }

    // MARK: - Private Methods

    private func sanitizeCacheKey(_ cacheKey: String) -> String {
        // Replace any characters that aren't filesystem-safe with underscores
        return cacheKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
