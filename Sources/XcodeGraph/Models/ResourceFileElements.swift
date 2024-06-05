import Foundation

public struct ResourceFileElements: Codable, Equatable {
    public var resources: [ResourceFileElement]

    public var privacyManifest: PrivacyManifest?

    public init(
        _ resources: [ResourceFileElement],
        privacyManifest: PrivacyManifest? = nil
    ) {
        self.resources = resources
        self.privacyManifest = privacyManifest
    }
}
