import Foundation

/// An enum that represents the type of xcframeworks output
public enum CacheXCFrameworkType: String {
    case device
    case simulator
}

/// An enum that represents the type of output that the caching feature can work with.
public enum CacheOutputType: CustomStringConvertible {
    /// Resource bundle built for the simulator
    case bundle

    /// Frameworks built for the simulator.
    case framework

    /// XCFrameworks built for the simulator and/or device.
    case xcframework(CacheXCFrameworkType?)

    public var description: String {
        switch self {
        case .bundle:
            return "bundle"
        case .framework:
            return "framework"
        case let .xcframework(type):
            switch type {
            case .device:
                return "device-xcframework"
            case .simulator:
                return "simulator-xcframework"
            case nil:
                return "xcframework"
            }
        }
    }
}

extension CacheOutputType: Equatable {}

extension CacheOutputType {
    public var isXCFramework: Bool {
        switch self {
        case .bundle, .framework:
            return false
        case .xcframework:
            return true
        }
    }

    public var shouldBuildForSimulator: Bool {
        switch self {
        case .bundle:
            return false
        case .framework:
            return true
        case let .xcframework(type):
            switch type {
            case .simulator, nil:
                return true
            case .device:
                return false
            }
        }
    }

    public var shouldBuildForDevice: Bool {
        switch self {
        case .bundle, .framework:
            return false
        case let .xcframework(type):
            switch type {
            case .device, nil:
                return true
            case .simulator:
                return false
            }
        }
    }
}
