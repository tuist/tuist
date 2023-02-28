import Foundation

/// An enum that represents the type of output that the caching feature can work with.
public enum CacheOutputType: CustomStringConvertible {
    /// Resource bundle built for the simulator
    case bundle

    /// Frameworks built for the simulator.
    case framework

    /// XCFrameworks built for the simulator and device.
    case xcframework

    /// XCFrameworks built for devices.
    case deviceXCFramework

    /// XCFrameworks built for simulators.
    case simulatorXCFramework

    public var description: String {
        switch self {
        case .bundle:
            return "bundle"
        case .framework:
            return "framework"
        case .xcframework:
            return "xcframework"
        case .deviceXCFramework:
            return "device-xcframework"
        case .simulatorXCFramework:
            return "simulator-xcframework"
        }
    }

    public var isXCFramework: Bool {
        switch self {
        case .bundle, .framework:
            return false
        case .xcframework, .deviceXCFramework, .simulatorXCFramework:
            return true
        }
    }
}
