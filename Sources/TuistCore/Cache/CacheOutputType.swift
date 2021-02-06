import Foundation

/// An enum that represents the type of output that the caching feature can work with.
public enum CacheOutputType: CustomStringConvertible {
    /// Frameworks built for the simulator.
    case framework

    /// XCFrameworks built for the simulator and device.
    case xcframework

    /// No output will be produced
    /// This is used eg. for testing where all we care about is whether a hash is present
    case none

    public var description: String {
        switch self {
        case .framework:
            return "framework"
        case .xcframework:
            return "xcframework"
        case .none:
            return "none"
        }
    }
}
