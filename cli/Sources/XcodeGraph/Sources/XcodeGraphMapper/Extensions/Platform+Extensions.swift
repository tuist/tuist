import XcodeGraph

extension Platform {
    /// Initializes a `Platform` instance from an SDK root string (e.g., "iphoneos", "macosx").
    /// Returns `nil` if no matching platform is found.
    init?(sdkroot: String) {
        guard let platform = Platform.allCases.first(where: { $0.xcodeSdkRoot == sdkroot }) else {
            return nil
        }
        self = platform
    }

    /// Returns a set of `Destination` values supported by this platform.
    var destinations: Destinations {
        switch self {
        case .iOS:
            return [.iPad, .iPhone, .macCatalyst, .macWithiPadDesign, .appleVisionWithiPadDesign]
        case .macOS:
            return [.mac]
        case .tvOS:
            return [.appleTv]
        case .watchOS:
            return [.appleWatch]
        case .visionOS:
            return [.appleVision]
        }
    }
}
