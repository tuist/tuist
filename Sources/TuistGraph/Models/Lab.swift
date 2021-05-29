import Foundation

/// Lab represents the configuration to connect to the server.
public struct Lab: Equatable, Hashable {
    /// Lab option.
    public enum Option: String, Codable, Equatable {
        case insights
    }

    /// The base URL that points to the lab server
    public let url: URL

    /// The project unique identifier.
    public let projectId: String

    /// Lab options.
    public let options: [Option]

    /// Initializes an instance of Lab.
    /// - Parameters:
    ///   - url: Lab server base URL.
    ///   - projectId: Project unique identifier.
    ///   - options: Lab options.
    public init(url: URL, projectId: String, options: [Option]) {
        self.url = url
        self.projectId = projectId
        self.options = options
    }
}
