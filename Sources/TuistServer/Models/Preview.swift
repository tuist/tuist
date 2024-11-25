import Foundation

public struct Preview: Equatable, Codable, Identifiable {
    public let id: String
    public let url: URL
    public let qrCodeURL: URL
    public let iconURL: URL
    public let bundleIdentifier: String?
    public var displayName: String?
}

extension Preview {
    init?(_ preview: Components.Schemas.Preview) {
        id = preview.id
        guard let url = URL(string: preview.url),
              let qrCodeURL = URL(string: preview.qr_code_url),
              let iconURL = URL(string: preview.icon_url)
        else { return nil }
        self.url = url
        self.qrCodeURL = qrCodeURL
        self.iconURL = iconURL
        bundleIdentifier = preview.bundle_identifier
        displayName = preview.display_name
    }
}

#if DEBUG
    extension Preview {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            // swiftlint:disable:this force_try,
            qrCodeURL: URL =
                URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/qr-code.svg")!,
            // swiftlint:disable:this force_try
            iconURL: URL =
                URL(string: "https://cloud.tuist.io/tuist/tuist/previews/preview-id/icon.png")!,
            // swiftlint:disable:this force_try
            bundleIdentifier: String? = "com.tuist.app",
            displayName: String? = "App"
        ) -> Self {
            .init(
                id: id,
                url: url,
                qrCodeURL: qrCodeURL,
                iconURL: iconURL,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName
            )
        }
    }
#endif
