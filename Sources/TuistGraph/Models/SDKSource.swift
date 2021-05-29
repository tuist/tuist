import Foundation

public enum SDKSource: String, Equatable, Codable {
    case developer // Platforms/iPhoneOS.platform/Developer/Library
    case system // Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library

    /// Returns the framework search path that should be used in Xcode to locate the SDK.
    public var frameworkSearchPath: String? {
        switch self {
        case .developer:
            return "$(PLATFORM_DIR)/Developer/Library/Frameworks"
        case .system:
            return nil
        }
    }
}
