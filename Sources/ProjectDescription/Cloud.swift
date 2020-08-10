import Foundation

/// Cloud represents the configuration to connect to the server.
public struct Cloud: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case url
        case projectId = "project_id"
        case options
    }

    /// Cloud option.
    public enum Option: String, Codable, Equatable {
        case insights
    }

    /// The base URL that points to the cloud server
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// Cloud options.
    public let options: [Option]

    /// Initializes a new Cloud configuration instance.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the cloud server.
    ///   - options: Cloud options.
    /// - Returns: A Cloud instance.
    public static func cloud(projectId: String, url: String, options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
