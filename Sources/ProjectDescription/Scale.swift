import Foundation

/// Scale represents the configuration to connect to the server.
public struct Scale: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case url
        case projectId = "project_id"
        case options
    }

    /// Scale option.
    public enum Option: String, Codable, Equatable {
        case insights
    }

    /// The base URL that points to the scale server
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// Scale options.
    public let options: [Option]

    /// Initializes a new Scale configuration instance.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the scale server.
    ///   - options: Scale options.
    /// - Returns: A Scale instance.
    public static func scale(projectId: String, url: String = "https://scale.tuist.io", options: [Option] = []) -> Scale {
        Scale(url: url, projectId: projectId, options: options)
    }
}
