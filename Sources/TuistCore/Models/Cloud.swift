import Foundation

/// Cloud reprensets the configuration to connect to the cloud.
public struct Cloud: Equatable, Hashable {
    /// The base URL that points to the cloud server
    public let url: URL

    /// The project unique identifier.
    public let projectId: String

    /// Initializes an instance of Cloud.
    /// - Parameters:
    ///   - url: Cloud server base URL.
    ///   - projectId: Project unique identifier.
    public init(url: URL, projectId: String) {
        self.url = url
        self.projectId = projectId
    }
}
