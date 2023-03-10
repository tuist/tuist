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
            if destination.contains(.all) {
                return "xcframework"
            }
            if destination.contains(.device) {
                return "device-xcframework"
            }
            if destination.contains(.simulator) {
                return "simulator-xcframework"
            }
            return "xcframework"
        }
    }
}
