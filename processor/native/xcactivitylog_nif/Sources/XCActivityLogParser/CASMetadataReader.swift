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

struct CASMetadataReader {
    private let fileSystem: FileSystem
    private let casMetadataPath: AbsolutePath

    init(fileSystem: FileSystem = FileSystem(), casMetadataPath: AbsolutePath) {
        self.fileSystem = fileSystem
        self.casMetadataPath = casMetadataPath
    }

    func readChecksum(nodeID: String) async -> String? {
        let safeNodeID = sanitize(nodeID)
        let path = casMetadataPath.appending(components: "nodes", safeNodeID)
        guard let data = try? await fileSystem.readFile(at: path) else { return nil }
        return String(data: Data(data), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func readOutputMetadata(checksum: String) async -> CASOutputMetadataEntry? {
        let path = casMetadataPath.appending(components: "cas", "\(checksum).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
    }

    func readKeyValueMetadata(key: String, operationType: String) async -> KeyValueMetadataEntry? {
        let safeKey = sanitizeCacheKey(key)
        let path = casMetadataPath.appending(components: "keyvalue", operationType, "\(safeKey).json")
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
