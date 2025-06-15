import Foundation

/// Server build run
public struct ServerBuild: Codable {
    public let id: String
    public let url: URL

    public init(
        id: String,
        url: URL
    ) {
        self.id = id
        self.url = url
    }
}

extension ServerBuild {
    init?(_ build: Components.Schemas.RunsBuild) {
        id = build.id
        guard let url = URL(string: build.url)
        else { return nil }
        self.url = url
    }
}

#if MOCKING
    extension ServerBuild {
        public static func test(
            id: String = "build-id",
            url: URL = URL(string: "https://tuist.dev/build-url")!
        ) -> Self {
            .init(
                id: id,
                url: url
            )
        }
    }
#endif
