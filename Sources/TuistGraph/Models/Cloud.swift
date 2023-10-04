import Foundation

/// Cloud represents the configuration to connect to the server.
public struct Cloud: Equatable, Hashable {
    /// Cloud option.
    public enum Option: String, Codable, Equatable {
        case disableAnalytics
        case optional
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

    /// Returns a new copy of `Cloud` with the given URL.
    /// - Parameter url: The URL to set in the new instance.
    /// - Returns: A new instance of Cloud.
    public func withURL(url: URL) -> Cloud {
        Cloud(
            url: url,
            projectId: projectId,
            options: options
        )
    }
}
