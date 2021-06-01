import Foundation

/// Lab represents the configuration to connect to the server.
public struct Lab: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case url
        case projectId = "project_id"
        case options
    }

    /// Lab option.
    public enum Option: String, Codable, Equatable {
        case insights
    }

    /// The base URL that points to the Lab server
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// Lab options.
    public let options: [Option]

    /// Initializes a new Lab configuration instance.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the Lab server.
    ///   - options: Lab options.
    /// - Returns: A Lab instance.
    public static func lab(projectId: String, url: String, options: [Option] = []) -> Lab {
        Lab(url: url, projectId: projectId, options: options)
    }
}
