@preconcurrency import CASAnalyticsDatabase
import FileSystem
import Foundation
import Path

struct CASOutputMetadataEntry: Decodable {
    let size: Int
    let duration: Double
    let compressedSize: Int
}

struct KeyValueMetadataEntry: Decodable {
    let duration: Double
}

struct CASMetadataReader: Sendable {
    private let db: Connection?
    private let legacyCASMetadataPath: AbsolutePath?
    private let fileSystem: FileSystem

    init(databasePath: AbsolutePath, legacyCASMetadataPath: AbsolutePath?) {
        self.fileSystem = FileSystem()
        if let db = try? Connection(databasePath.pathString, readonly: true) {
            self.db = db
            self.legacyCASMetadataPath = nil
        } else {
            self.db = nil
            self.legacyCASMetadataPath = legacyCASMetadataPath
        }
    }

    func readChecksum(nodeID: String) async -> String? {
        if let db {
            return try? db.pluck(
                NodesSchema.table.select(NodesSchema.checksum).filter(NodesSchema.key == nodeID)
            )?[NodesSchema.checksum]
        }

        guard let legacyCASMetadataPath else { return nil }
        let path = legacyCASMetadataPath.appending(components: "nodes", sanitize(nodeID))
        guard let data = try? await fileSystem.readFile(at: path) else { return nil }
        return String(data: Data(data), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func readOutputMetadata(checksum: String) async -> CASOutputMetadataEntry? {
        if let db {
            guard let row = try? db.pluck(
                CASOutputsSchema.table.filter(CASOutputsSchema.key == checksum)
            ) else { return nil }
            return CASOutputMetadataEntry(
                size: row[CASOutputsSchema.size],
                duration: row[CASOutputsSchema.duration],
                compressedSize: row[CASOutputsSchema.compressedSize]
            )
        }

        guard let legacyCASMetadataPath else { return nil }
        let path = legacyCASMetadataPath.appending(components: "cas", "\(checksum).json")
        return try? await fileSystem.readJSONFile(at: path)
    }

    func readKeyValueMetadata(key: String, operationType: String) async -> KeyValueMetadataEntry? {
        if let db {
            guard let row = try? db.pluck(
                KeyValueMetadataSchema.table.filter(
                    KeyValueMetadataSchema.key == key && KeyValueMetadataSchema.operationType == operationType
                )
            ) else { return nil }
            return KeyValueMetadataEntry(duration: row[KeyValueMetadataSchema.duration])
        }

        guard let legacyCASMetadataPath else { return nil }
        let path = legacyCASMetadataPath.appending(
            components: "keyvalue", operationType, "\(sanitizeCacheKey(key)).json"
        )
        return try? await fileSystem.readJSONFile(at: path)
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func sanitizeCacheKey(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
