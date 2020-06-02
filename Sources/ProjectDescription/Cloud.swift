import Foundation

/// Cloud reprensets the configuration to connect to the cloud.
public struct Cloud: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case url
        case projectId = "project_id"
        case options
    }

    /// Cloud option.
    public enum Option: String, Codable, Equatable {
        /// Enable collecting insights from your projects.
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
    ///   - url: Base URL to the cloud server.
    ///   - projectId: Project unique identifier.
    ///   - options: Cloud options.
    /// - Returns: A Cloud instance.
    public static func cloud(url: String, projectId: String, options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
