import Foundation

/// It's used by build files that represent outputs from other targets.
/// Xcode projects use this flag for the build system to determine
/// what dependencies should be built. For example, if it's an iOS
/// app with Catalyst enabled, frameworks that are iOS-only should
/// not be compiled.
/// Context: https://github.com/tuist/tuist/pull/3152
public enum BuildFilePlatformFilter: Comparable, Hashable {
    case ios
    case catalyst

    public var xcodeprojValue: String {
        switch self {
        case .catalyst:
            return "maccatalyst"
        case .ios:
            return "ios"
        }
    }
}
