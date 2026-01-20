@preconcurrency import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

/// Protocol for storing and retrieving CAS output metadata
@Mockable
public protocol CASOutputMetadataStoring: Sendable {
    /// Store metadata for a CAS output identified by CAS ID
    func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws

    /// Retrieve metadata for a CAS output
    func metadata(for casID: String) async throws -> CASOutputMetadata?
}

public struct CASOutputMetadataStore: CASOutputMetadataStoring {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws {
        let casDirectory = Environment.current.stateDirectory.appending(component: "cas")
        try await fileSystem.makeDirectory(at: casDirectory)

        let sanitizedCasID = sanitizeCasID(casID)
        let metadataFilePath = casDirectory.appending(component: "\(sanitizedCasID).json")

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        if try await fileSystem.exists(metadataFilePath) {
            try await fileSystem.remove(metadataFilePath)
        }

        try await fileSystem.writeText(jsonString, at: metadataFilePath)
    }

    public func metadata(for casID: String) async throws -> CASOutputMetadata? {
        let casDirectory = Environment.current.stateDirectory.appending(component: "cas")
        let sanitizedCasID = sanitizeCasID(casID)
        let metadataFilePath = casDirectory.appending(component: "\(sanitizedCasID).json")

        guard try await fileSystem.exists(metadataFilePath) else {
            return nil
        }

        let jsonString = try await fileSystem.readTextFile(at: metadataFilePath)
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        return try decoder.decode(CASOutputMetadata.self, from: jsonData)
    }

    // MARK: - Private Methods

    private func sanitizeCasID(_ casID: String) -> String {
        // Replace any characters that aren't filesystem-safe with underscores
        return casID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
