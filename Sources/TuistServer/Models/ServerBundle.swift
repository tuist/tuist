import Foundation

public struct ServerBundle {
    public let url: URL

    init(
        url: URL
    ) {
        self.url = url
    }

    init?(_ bundle: Components.Schemas.Bundle) {
        guard let url = URL(string: bundle.url)
        else { return nil }
        self.url = url
    }
}

#if DEBUG
    extension ServerBundle {
        public static func test(
            url: URL = URL(string: "https://tuist.dev/bundle")!
        ) -> ServerBundle {
            ServerBundle(
                url: url
            )
        }
    }
#endif
