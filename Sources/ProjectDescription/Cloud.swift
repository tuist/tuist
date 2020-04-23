import Foundation

/// Cloud reprensets the configuration to connect to the cloud.
public struct Cloud: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case url
        case projectId = "project_id"
    }

    /// The base URL that points to the cloud server
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// Initializes a new Cloud configuration instance.
    /// - Parameters:
    ///   - url: Base URL to the cloud server.
    ///   - projectId: Project unique identifier.
    /// - Returns: A Cloud instance.
    public static func cloud(url: String, projectId: String) -> Cloud {
        Cloud(url: url, projectId: projectId)
    }
}
