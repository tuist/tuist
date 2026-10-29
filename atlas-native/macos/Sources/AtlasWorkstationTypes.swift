#if os(macOS)
import Foundation

struct AtlasWorkstationFolder: Codable, Identifiable, Equatable {
    var id = UUID().uuidString.lowercased()
    let path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct AtlasWorkstationConfiguration: Codable, Equatable {
    var id = UUID().uuidString.lowercased()
    var name = "My Mac"
    var enabled = false
    var terminal = false
    var keepAwake = false
    var home = false
    var homeId = UUID().uuidString.lowercased()
    var folders: [AtlasWorkstationFolder] = []
    var projectDirectories: [AtlasWorkstationFolder] = []
}

struct AtlasWorkstationCommand: Decodable, Equatable {
    struct Arguments: Decodable, Equatable {
        let projectId: String
        let path: String?
        let command: String?
    }
    let id: String
    let tool: String
    let arguments: Arguments
    var executionTimeoutSeconds = 0
    let digest: String
    let claimToken: String?

    func matches(_ other: Self) -> Bool {
        id == other.id && tool == other.tool && arguments == other.arguments
            && digest == other.digest && executionTimeoutSeconds == other.executionTimeoutSeconds
    }
}

struct AtlasWorkstationSnapshot: Decodable {
    var sequence: UInt64?
    var commands: [AtlasWorkstationCommand]?
    var error: String?
    var needsSession: Bool?
}

struct AtlasWorkstationResult {
    let success: Bool
    let output: String
}
#endif
