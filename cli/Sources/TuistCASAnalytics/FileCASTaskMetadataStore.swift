import FileSystem
import Foundation
import Path
import TuistSupport

public final class FileCASTaskMetadataStore: CASTaskMetadataStoring {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func storeMetadata(_ metadata: CASTaskMetadata, for casID: String) async throws {
        let casDirectory = Environment.current.stateDirectory.appending(component: "cas")
        try await ensureCasDirectoryExists(casDirectory)

        let sanitizedCasID = sanitizeCasID(casID)
        let metadataFilePath = casDirectory.appending(component: "\(sanitizedCasID).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        let jsonData = try encoder.encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        try await fileSystem.writeText(jsonString, at: metadataFilePath)
    }

    public func metadata(for casID: String) async throws -> CASTaskMetadata? {
        let casDirectory = Environment.current.stateDirectory.appending(component: "cas")
        let sanitizedCasID = sanitizeCasID(casID)
        let metadataFilePath = casDirectory.appending(component: "\(sanitizedCasID).json")

        guard try await fileSystem.exists(metadataFilePath) else {
            return nil
        }

        let jsonString = try await fileSystem.readTextFile(at: metadataFilePath)
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback to standard ISO8601 format if fractional seconds parsing fails
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
        return try decoder.decode(CASTaskMetadata.self, from: jsonData)
    }

    // MARK: - Private Methods

    private func ensureCasDirectoryExists(_ casDirectory: AbsolutePath) async throws {
        if try await !fileSystem.exists(casDirectory) {
            try await fileSystem.makeDirectory(at: casDirectory)
        }
    }

    private func sanitizeCasID(_ casID: String) -> String {
        // Replace any characters that aren't filesystem-safe with underscores
        return casID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
