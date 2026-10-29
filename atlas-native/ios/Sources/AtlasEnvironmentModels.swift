import Foundation

typealias AtlasEnvironmentRequest = ([String: Any]) async throws -> Data

struct AtlasEnvironmentProject: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

struct AtlasPersonalEnvironment: Decodable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
    let online: Bool
    let terminal: Bool
    let display: Bool
    let projects: [AtlasEnvironmentProject]
    let provider: String?
    let providerState: String?

    var native: Bool { provider == nil || provider == "native" }
}

struct AtlasEnvironmentOverview: Decodable {
    struct Provider: Decodable, Identifiable {
        let id: String
        let name: String
    }
    let ownerId: String
    let environments: [AtlasPersonalEnvironment]
    let providers: [Provider]?
}

struct AtlasEnvironmentSelection: Decodable {
    struct Thread: Decodable {
        let id: String
        let environmentId: String?
        let environmentName: String?
        let projectId: String?
    }
    let thread: Thread
}

struct AtlasEnvironmentJob: Decodable, Identifiable, Equatable {
    let id: String
    let messageId: String
    let environmentId: String
    let environmentName: String
    let projectId: String
    let projectName: String
    let digest: String
    let command: String
    let status: String
    let output: String
    let success: Bool?
    let cancelRequested: Bool
    let progressSequence: UInt64
    let executionTimeoutSeconds: Int

    var active: Bool { ["queued", "claimed"].contains(status) }
    var phase: String {
        if cancelRequested && active { return "Stopping · waiting for \(executionTimeoutSeconds == 1800 ? "Mac" : "environment")" }
        switch status {
        case "queued": return executionTimeoutSeconds == 1800 ? "Waiting for Mac" : "Waiting for environment"
        case "claimed": return "Running on \(environmentName)"
        case "settled": return success == true ? "Completed" : "Stopped or failed"
        case "cancelled": return "Cancelled before starting"
        case "expired": return "Expired before starting"
        default: return "Outcome unknown · not retried"
        }
    }
}

enum AtlasEnvironmentCoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
