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
    struct Edit: Decodable, Equatable {
        let oldText: String
        let newText: String
    }
    struct Arguments: Decodable, Equatable {
        let projectId: String
        let path: String?
        let command: String?
        var threadId: String?
        var title: String?
        var offset: Int?
        var limit: Int?
        var timeout: Int?
        var content: String?
        var edits: [Edit]?
    }
    let id: String
    let tool: String
    let arguments: Arguments
    var executionTimeoutSeconds = 0
    let digest: String
    let claimToken: String?

    var coding: Bool { ["read", "bash", "edit", "write"].contains(tool) }
    var terminal: Bool { ["bash", "environment_terminal"].contains(tool) }

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
