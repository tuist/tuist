import Foundation

/// A cloud configuration, used for remote caching.
public struct Cloud: Codable, Equatable, Sendable {
    /// Options for cloud configuration.
    public enum Option: String, Codable, Equatable, Sendable {
        /// Marks whether the Tuist server authentication is optional.
        /// If present, the interaction with the Tuist server will be skipped (instead of failing) if a user is not authenticated.
        case optional
    }

    /// The base URL that points to the Cloud server.
    public var url: String

    /// The project unique identifier.
    public var projectId: String

    /// The configuration options.
    public var options: [Option]

    /// Returns a generic cloud configuration.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the Cloud server.
    ///   - options: Cloud options.
    /// - Returns: A Cloud instance.
    @available(*, deprecated, message: "Use the `fullHandle` and `url` properties directly in the `Config`")
    public static func cloud(projectId: String, url: String = "https://tuist.dev", options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
