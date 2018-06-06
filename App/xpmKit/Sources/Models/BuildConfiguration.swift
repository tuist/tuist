import Foundation

/// Build configuration.
///
/// - debug: debug build configuration.
/// - release: release build configuration.
enum BuildConfiguration: String {
    case debug
    case release
}

// MARK: - BuildConfiguration (Xcode)

extension BuildConfiguration: XcodeRepresentable {
    /// Returns the Xcode value for the build configuration.
    var xcodeValue: String {
        switch self {
        case .debug: return "Debug"
        case .release: return "Release"
        }
    }
}
