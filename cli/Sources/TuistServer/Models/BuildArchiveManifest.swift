import Foundation

public struct BuildArchiveManifest: Codable {
    public let cacheUploadEnabled: Bool
    public let macOSVersion: String
    public let modelIdentifier: String?
    public let xcodeVersion: String?

    public init(
        cacheUploadEnabled: Bool,
        macOSVersion: String,
        modelIdentifier: String?,
        xcodeVersion: String?
    ) {
        self.cacheUploadEnabled = cacheUploadEnabled
        self.macOSVersion = macOSVersion
        self.modelIdentifier = modelIdentifier
        self.xcodeVersion = xcodeVersion
    }

    enum CodingKeys: String, CodingKey {
        case cacheUploadEnabled = "cache_upload_enabled"
        case macOSVersion = "macos_version"
        case modelIdentifier = "model_identifier"
        case xcodeVersion = "xcode_version"
    }
}
