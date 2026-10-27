import Foundation

public struct PrivacyManifest: Codable, Equatable, Sendable {
    public var tracking: Bool

    public var trackingDomains: [String]

    public var collectedDataTypes: [[String: Plist.Value]]

    public var accessedApiTypes: [[String: Plist.Value]]

    public init(
        tracking: Bool,
        trackingDomains: [String],
        collectedDataTypes: [[String: Plist.Value]],
        accessedApiTypes: [[String: Plist.Value]]
    ) {
        self.tracking = tracking
        self.trackingDomains = trackingDomains
        self.collectedDataTypes = collectedDataTypes
        self.accessedApiTypes = accessedApiTypes
    }
}
