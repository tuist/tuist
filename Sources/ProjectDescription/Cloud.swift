import Foundation

/// Cloud represents the configuration to connect to the server.
public struct Cloud: Codable, Equatable {
    /// Cloud option.
    public enum Option: String, Codable, Equatable {
        case analytics
        /// Marks whether cloud connection is optional.
        /// If not present, tuist commands will fail regardless of whether an authentication token is available locally from `tuist cloud auth` or not.
        case optional
    }

    /// The base URL that points to the Cloud server
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// Cloud options.
    public let options: [Option]

    /// Initializes a new Cloud configuration instance.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the Cloud server.
    ///   - options: Cloud options.
    /// - Returns: A Cloud instance.
    public static func cloud(projectId: String, url: String, options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
