import Foundation

public struct PreviewUploadResult: Sendable, Equatable, Codable {
    public let id: String
    public let url: URL
    public let qrCodeURL: URL

    public init(id: String, url: URL, qrCodeURL: URL) {
        self.id = id
        self.url = url
        self.qrCodeURL = qrCodeURL
    }
}

#if DEBUG
    extension PreviewUploadResult {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            qrCodeURL: URL =
                URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/qr-code.svg")!
        ) -> Self {
            .init(
                id: id,
                url: url,
                qrCodeURL: qrCodeURL
            )
        }
    }
#endif
