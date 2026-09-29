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

struct ServedRegions: Sendable {
    struct Key: Hashable, Sendable {
        let key: String
        let operationType: String
    }

    let regions: [Key: String]

    func region(key: String, operationType: String) -> String? {
        regions[Key(key: key, operationType: operationType)]
    }
}

struct CASMetadataReader: Sendable {
    private let db: Connection?
    private let legacyCASMetadataPath: AbsolutePath?
    private let fileSystem: FileSystem

    init(databasePath: AbsolutePath, legacyCASMetadataPath: AbsolutePath?) {
        self.fileSystem = FileSystem()
        // Build archives contain a checkpointed snapshot without WAL sidecars.
        // On macOS, read-only WAL snapshots failed queries without those sidecars.
        // Immutable mode handles that case; the production Linux reader already works.
        let location = Connection.Location.uri(
            URL(fileURLWithPath: databasePath.pathString).absoluteString,
            parameters: [.immutable(true)]
        )
        if let db = try? Connection(location, readonly: true) {
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

    /// Every region the CAS proxy recorded, by operation type and key. Read in
    /// one pass: the table holds at most an hour of the machine's operations,
    /// and a build looks up one row per key and output. Databases written
    /// before the proxy recorded it (or by the legacy writer) have no table,
    /// which reads as empty.
    func readServedRegions() -> ServedRegions {
        guard let db,
              let rows = try? db.prepare(
                  ServedBySchema.table.select(ServedBySchema.key, ServedBySchema.operationType, ServedBySchema.region)
              )
        else { return ServedRegions(regions: [:]) }
        var regions = [ServedRegions.Key: String]()
        for row in rows {
            guard let key = try? row.get(ServedBySchema.key),
                  let operationType = try? row.get(ServedBySchema.operationType),
                  let region = try? row.get(ServedBySchema.region),
                  !region.isEmpty
            else { continue }
            regions[ServedRegions.Key(key: key, operationType: operationType)] = region
        }
        return ServedRegions(regions: regions)
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
