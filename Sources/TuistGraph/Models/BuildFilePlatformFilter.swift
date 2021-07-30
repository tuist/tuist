import Foundation

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
