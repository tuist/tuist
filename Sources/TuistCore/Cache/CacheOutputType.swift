import Foundation

/// An enum that represents the type of output that the caching feature can work with.
public enum CacheOutputType: CustomStringConvertible, Equatable {
    /// Resource bundle built for the simulator
    case bundle

    /// Frameworks built for the simulator.
    case framework

    /// XCFrameworks built for the simulator and/or device.
    case xcframework(CacheXCFrameworkDestination)

    public var description: String {
        switch self {
        case .bundle:
            return "bundle"
        case .framework:
            return "framework"
        case let .xcframework(destination):
            switch destination {
            case [.device, .simulator]:
                return "xcframework"
            case .device:
                return "device-xcframework"
            case .simulator:
                return "simulator-xcframework"
            default:
                fatalError("xcframework should contain at least one destination")
            }
        }
    }
}
