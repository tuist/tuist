import Foundation

/// Cloud represents the configuration to connect to the server.
public struct Cloud: Equatable, Hashable {
    /// Cloud option.
    public enum Option: String, Codable, Equatable {
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
}

#if DEBUG
    extension Cloud {
        public static func test(
            url: URL = URL(string: "https://test.tuist.io")!,
            projectId: String = "123",
            options: [Cloud.Option] = []
        ) -> Cloud {
            Cloud(url: url, projectId: projectId, options: options)
        }
    }
#endif
