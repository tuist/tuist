import Foundation

public enum ServerBuildStatus: String, Codable {
    case success
    case failure
    case processing
    case failedProcessing = "failed_processing"
}

/// Server build run
public struct ServerBuild: Codable {
    public let id: String
    public let url: URL
    public let status: ServerBuildStatus?

    public init(
        id: String,
        url: URL,
        status: ServerBuildStatus? = nil
    ) {
        self.id = id
        self.url = url
        self.status = status
    }

    init?(_ build: Components.Schemas.RunsBuild) {
        id = build.id
        guard let url = URL(string: build.url)
        else { return nil }
        self.url = url
        switch build.status {
        case .success:
            status = .success
        case .failure:
            status = .failure
        case .processing:
            status = .processing
        case .failed_processing:
            status = .failedProcessing
        case .none:
            status = nil
        }
    }

    #if MOCKING
        public static func test(
            id: String = "build-id",
            url: URL = URL(string: "https://tuist.dev/build-url")!,
            status: ServerBuildStatus? = nil
        ) -> Self {
            .init(
                id: id,
                url: url,
                status: status
            )
        }
    #endif
}
