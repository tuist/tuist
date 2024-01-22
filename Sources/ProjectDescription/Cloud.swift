import Foundation

/// A cloud configuration, used for remote caching.
public struct Cloud: Codable, Equatable {
    /// Options for cloud configuration.
    public enum Option: String, Codable, Equatable {
        /// Marks whether cloud connection is optional.
        /// If not present, tuist commands will fail regardless of whether an authentication token is available locally from
        /// `tuist cloud auth` or not.
        case optional
    }

    /// The base URL that points to the Cloud server.
    public var url: String = "https://cloud.tuist.io"

    /// The project unique identifier.
    public var projectId: String

    /// The configuration options.
    public var options: [Option] = []
}
