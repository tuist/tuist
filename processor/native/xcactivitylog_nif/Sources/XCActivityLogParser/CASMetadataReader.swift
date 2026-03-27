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
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
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

// MARK: - Table Schemas

private enum CASOutputsSchema {
    static let table = Table("cas_outputs")
    static let key = SQLite.Expression<String>("key")
    static let size = SQLite.Expression<Int>("size")
    static let duration = SQLite.Expression<Double>("duration")
    static let compressedSize = SQLite.Expression<Int>("compressed_size")
}

private enum NodesSchema {
    static let table = Table("nodes")
    static let key = SQLite.Expression<String>("key")
    static let checksum = SQLite.Expression<String>("checksum")
}

private enum KeyValueMetadataSchema {
    static let table = Table("keyvalue_metadata")
    static let key = SQLite.Expression<String>("key")
    static let operationType = SQLite.Expression<String>("operation_type")
    static let duration = SQLite.Expression<Double>("duration")
}
