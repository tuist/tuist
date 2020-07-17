import Foundation

/// Scale represents the configuration to connect to the server.
public struct Scale: Equatable, Hashable {
    /// Scale option.
    public enum Option: String, Codable, Equatable {
        case insights
    }

    /// The base URL that points to the scale server
    public let url: URL

    /// The project unique identifier.
    public let projectId: String

    /// Scale options.
    public let options: [Option]

    /// Initializes an instance of Scale.
    /// - Parameters:
    ///   - url: Scale server base URL.
    ///   - projectId: Project unique identifier.
    ///   - options: Scale options.
    public init(url: URL, projectId: String, options: [Option]) {
        self.url = url
        self.projectId = projectId
        self.options = options
    }
}
