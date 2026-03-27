import Foundation
import Path
@preconcurrency import SQLite

struct CASOutputMetadataEntry {
    let size: Int
    let duration: Double
    let compressedSize: Int
}

struct KeyValueMetadataEntry {
    let duration: Double
}

struct CASMetadataReader {
    private let db: Connection?

    init(databasePath: AbsolutePath) {
        if FileManager.default.fileExists(atPath: databasePath.pathString) {
            self.db = try? Connection(databasePath.pathString, readonly: true)
        } else {
            self.db = nil
        }
    }

    func readChecksum(nodeID: String) -> String? {
        guard let db else { return nil }
        let table = Table("nodes")
        let keyCol = SQLite.Expression<String>("key")
        let checksumCol = SQLite.Expression<String>("checksum")
        return try? db.pluck(
            table.select(checksumCol).filter(keyCol == nodeID)
        )?[checksumCol]
    }

    func readOutputMetadata(checksum: String) -> CASOutputMetadataEntry? {
        guard let db else { return nil }
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

    func readKeyValueMetadata(key: String, operationType: String) -> KeyValueMetadataEntry? {
        guard let db else { return nil }
        let table = Table("keyvalue_metadata")
        let keyCol = SQLite.Expression<String>("key")
        let opCol = SQLite.Expression<String>("operation_type")
        let durationCol = SQLite.Expression<Double>("duration")
        guard let row = try? db.pluck(
            table.filter(keyCol == key && opCol == operationType)
        ) else { return nil }
        return KeyValueMetadataEntry(duration: row[durationCol])
    }
}
