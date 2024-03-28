import Foundation

public struct ResourceFileElements: Codable, Equatable {
    public var resources: [ResourceFileElement]

    public var privacyManifest: PrivacyManifest?

    public static func resources(_ resources: [ResourceFileElement], privacyManifest: PrivacyManifest? = nil) -> Self {
        self.init(resources: resources, privacyManifest: privacyManifest)
    }
}

public struct PrivacyManifest: Codable, Equatable {
    public var tracking: Bool

    public var trackingDomains: [String]

    public var collectedDataTypes: [[String: Plist.Value]]

    public var accessedApiTypes: [[String: Plist.Value]]

    /// - Parameters:
    ///   - tracking: A Boolean that indicates whether your app or third-party SDK uses data for tracking as defined under the App
    /// Tracking Transparency framework. For more information, see [User Privacy and Data
    /// Use](https://developer.apple.com/app-store/user-privacy-and-data-use/).
    ///   - trackingDomains: An array of strings that lists the internet domains your app or third-party SDK connects to that
    /// engage in tracking. If the user has not granted tracking permission through the App Tracking Transparency framework,
    /// network requests to these domains fail and your app receives an error. If you set `tracking` to true then you need to
    /// provide at least one internet domain in NSPrivacyTrackingDomains; otherwise, you can provide zero or more domains.
    ///   - collectedDataTypes: An array of dictionaries that describes the data types your app or third-party SDK collects. For
    /// information on the keys and values to use in the dictionaries, see [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_data_use_in_privacy_manifests).
    ///   - accessedApiTypes: An array of dictionaries that describe the API types your app or third-party SDK accesses that have
    /// been designated as APIs that require reasons to access. For information on the keys and values to use in the dictionaries,
    /// see [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api).
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
