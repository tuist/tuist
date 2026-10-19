import XcodeGraph

extension XCFrameworkInfoPlist.Library {
    /// The `sdk=<sdk>*` build setting condition that selects this slice. Mac Catalyst slices share
    /// `sdk=macosx*` with macOS ones.
    public var sdkCondition: String {
        let graphPlatform = platform.graphPlatform
        switch platformVariant {
        case .simulator:
            if let simulatorSDK = graphPlatform.xcodeSimulatorSDK {
                return "sdk=\(simulatorSDK)*"
            }
            return "sdk=\(graphPlatform.xcodeSdkRoot)*"
        case .maccatalyst:
            return "sdk=macosx*"
        case nil:
            return "sdk=\(graphPlatform.xcodeSdkRoot)*"
        }
    }
}

extension XCFrameworkInfoPlist.Library.Platform {
    fileprivate var graphPlatform: XcodeGraph.Platform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        case .visionOS: return .visionOS
        }
    }
}
