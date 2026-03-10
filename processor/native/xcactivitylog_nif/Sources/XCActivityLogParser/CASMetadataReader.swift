import Foundation

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

enum CASMetadataReader {
    static func readChecksum(nodeID: String, casMetadataPath: String) -> String? {
        let nodesDir = (casMetadataPath as NSString).appendingPathComponent("nodes")
        let safeNodeID = nodeID.replacingOccurrences(of: "/", with: "_")
        let path = (nodesDir as NSString).appendingPathComponent("\(safeNodeID).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(CASNodeEntry.self, from: data)
        else { return nil }
        return entry.checksum
    }

    static func readOutputMetadata(checksum: String, casMetadataPath: String) -> CASOutputMetadataEntry? {
        let casDir = (casMetadataPath as NSString).appendingPathComponent("cas")
        let path = (casDir as NSString).appendingPathComponent("\(checksum).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(CASOutputMetadataEntry.self, from: data)
        else { return nil }
        return entry
    }

    static func readKeyValueMetadata(key: String, operationType: String, casMetadataPath: String) -> KeyValueMetadataEntry? {
        let kvDir = (casMetadataPath as NSString).appendingPathComponent("keyvalue")
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
        let path = (kvDir as NSString).appendingPathComponent("\(safeKey)_\(operationType).json")
        guard let data = FileManager.default.contents(atPath: path),
              let entry = try? JSONDecoder().decode(KeyValueMetadataEntry.self, from: data)
        else { return nil }
        return entry
    }
}
