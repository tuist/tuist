import Foundation

public struct Preview: Equatable, Codable {
    public let id: String
    public let url: URL
    public let qrCodeURL: URL
}

extension Preview {
    init?(_ preview: Components.Schemas.Preview) {
        id = preview.id
        guard let url = URL(string: preview.url),
              let qrCodeURL = URL(string: preview.qr_code_url)
        else { return nil }
        self.url = url
        self.qrCodeURL = qrCodeURL
    }
}

#if DEBUG
    extension Preview {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://cloud.tuist.io/tuist/tuist/previews/preview-id")!,
            // swiftlint:disable:this force_try,
            qrCodeURL: URL =
                URL(string: "https://cloud.tuist.io/tuist/tuist/previews/preview-id/qr-code.svg")! // swiftlint:disable:this force_try
        ) -> Self {
            .init(
                id: id,
                url: url,
                qrCodeURL: qrCodeURL
            )
        }
    }
#endif
