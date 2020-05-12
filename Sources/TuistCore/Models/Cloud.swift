import Foundation

/// Cloud reprensets the configuration to connect to the cloud.
public struct Cloud: Equatable, Hashable {
    /// Cloud option.
    public enum Option: String, Codable, Equatable {
        /// Enable collecting insights from your projects.
        case insights
    }

    /// The base URL that points to the cloud server
    public let url: URL

    /// The project unique identifier.
    public let projectId: String

    /// Cloud options.
    public let options: [Option]

    /// Initializes an instance of Cloud.
    /// - Parameters:
    ///   - url: Cloud server base URL.
    ///   - projectId: Project unique identifier.
    ///   - options: Cloud options.
    public init(url: URL, projectId: String, options: [Option]) {
        self.url = url
        self.projectId = projectId
        self.options = options
    }
}
