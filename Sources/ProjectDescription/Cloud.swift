import Foundation

/// A cloud configuration, used for remote caching.
public struct Cloud: Codable, Equatable {
    /// Options for cloud configuration.
    public enum Option: String, Codable, Equatable {
        /// Marks whether Tuist Cloud authentication is optional.
        /// If present, the interaction with Tuist Cloud will be skipped (instead of failing) if a user is not authenticated.
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
    public static func cloud(projectId: String, url: String = "https://cloud.tuist.io", options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
