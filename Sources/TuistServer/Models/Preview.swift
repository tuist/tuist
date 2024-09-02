import Foundation

public struct Preview: Equatable {
    public let id: String
    public let url: URL
}

#if DEBUG
    extension Preview {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://cloud.tuist.io/tuist/tuist/previews/preview-id")! // swiftlint:disable:this force_try
        ) -> Self {
            .init(
                id: id,
                url: url
            )
        }
    }
#endif
