import Foundation

/// A cloud configuration, used for remote caching.
public struct Cloud: Codable, Equatable {
    /// Options for cloud configuration.
    public enum Option: String, Codable, Equatable {
        /// Enables sending analytics to cloud dashboard.
        @available(
            *,
            deprecated,
            message: "Analytics are sent to the cloud backend by default. Use `disableAnalytics` to disable this feature."
        )
        case analytics

        /// Disables sending analytics to cloud dashboard.
        case disableAnalytics

        /// Marks whether cloud connection is optional.
        /// If not present, tuist commands will fail regardless of whether an authentication token is available locally from `tuist cloud auth` or not.
        case optional
    }

    /// The base URL that points to the Cloud server.
    public let url: String

    /// The project unique identifier.
    public let projectId: String

    /// The configuration options.
    public let options: [Option]

    /// Returns a generic cloud configuration.
    /// - Parameters:
    ///   - projectId: Project unique identifier.
    ///   - url: Base URL to the Cloud server.
    ///   - options: Cloud options.
    /// - Returns: A Cloud instance.
    public static func cloud(projectId: String, url: String, options: [Option] = []) -> Cloud {
        Cloud(url: url, projectId: projectId, options: options)
    }
}
