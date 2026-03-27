import FileSystem
import Foundation
import Path
@preconcurrency import SQLite

struct CASOutputMetadataEntry: Decodable {
    let size: Int
    let duration: Double
    let compressedSize: Int
}

struct KeyValueMetadataEntry: Decodable {
    let duration: Double
}

struct CASMetadataReader {
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
            let table = Table("nodes")
            let keyCol = SQLite.Expression<String>("key")
            let checksumCol = SQLite.Expression<String>("checksum")
            return try? db.pluck(
                table.select(checksumCol).filter(keyCol == nodeID)
            )?[checksumCol]
        }

        guard let legacyCASMetadataPath else { return nil }
        let safeNodeID = sanitize(nodeID)
        let path = legacyCASMetadataPath.appending(components: "nodes", safeNodeID)
        guard let data = try? await fileSystem.readFile(at: path) else { return nil }
        return String(data: Data(data), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func readOutputMetadata(checksum: String) async -> CASOutputMetadataEntry? {
        if let db {
            let table = Table("cas_outputs")
            let keyCol = SQLite.Expression<String>("key")
            let sizeCol = SQLite.Expression<Int>("size")
            let durationCol = SQLite.Expression<Double>("duration")
            let compressedSizeCol = SQLite.Expression<Int>("compressed_size")
            guard let row = try? db.pluck(table.filter(keyCol == checksum)) else { return nil }
            return CASOutputMetadataEntry(
                size: row[sizeCol],
                duration: row[durationCol],
                compressedSize: row[compressedSizeCol]
            )
        }

        guard let legacyCASMetadataPath else { return nil }
        let path = legacyCASMetadataPath.appending(components: "cas", "\(checksum).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
    }

    func readKeyValueMetadata(key: String, operationType: String) async -> KeyValueMetadataEntry? {
        if let db {
            let table = Table("keyvalue_metadata")
            let keyCol = SQLite.Expression<String>("key")
            let opCol = SQLite.Expression<String>("operation_type")
            let durationCol = SQLite.Expression<Double>("duration")
            guard let row = try? db.pluck(
                table.filter(keyCol == key && opCol == operationType)
            ) else { return nil }
            return KeyValueMetadataEntry(duration: row[durationCol])
        }

        guard let legacyCASMetadataPath else { return nil }
        let safeKey = sanitizeCacheKey(key)
        let path = legacyCASMetadataPath.appending(components: "keyvalue", operationType, "\(safeKey).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(KeyValueMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
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
