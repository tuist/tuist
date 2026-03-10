import FileSystem
import Foundation
import Path

struct CASNodeEntry: Decodable {
    let checksum: String
}

struct CASOutputMetadataEntry: Decodable {
    let size: Int
    let duration: Double
    let compressed_size: Int
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
        let safeNodeID = nodeID.replacingOccurrences(of: "/", with: "_")
        let path = casMetadataPath.appending(components: "nodes", "\(safeNodeID).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(CASNodeEntry.self, from: Data(data))
        else { return nil }
        return entry.checksum
    }

    func readOutputMetadata(checksum: String) async -> CASOutputMetadataEntry? {
        let path = casMetadataPath.appending(components: "cas", "\(checksum).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
    }

    func readKeyValueMetadata(key: String, operationType: String) async -> KeyValueMetadataEntry? {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
        let path = casMetadataPath.appending(components: "keyvalue", "\(safeKey)_\(operationType).json")
        guard let data = try? await fileSystem.readFile(at: path),
              let entry = try? JSONDecoder().decode(KeyValueMetadataEntry.self, from: Data(data))
        else { return nil }
        return entry
    }
}
