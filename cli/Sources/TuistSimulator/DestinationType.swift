import Foundation
import XcodeGraph

/// Represents a destination type either for a simulator or a device with a given platform.
public enum DestinationType: Hashable, Sendable, Codable, Equatable, CustomStringConvertible {
    case simulator(Platform)
    case device(Platform)
    case android

    public func buildProductDestinationPathComponent(
        for configuration: String
    ) -> String {
        switch self {
        case .device(.macOS), .simulator(.macOS):
            return configuration
        case let .device(platform):
            return "\(configuration)-\(platform.xcodeDeviceSDK)"
        case let .simulator(platform):
            return "\(configuration)-\(platform.xcodeSimulatorSDK!)"
        case .android:
            return configuration
        }
    }

    public var description: String {
        switch self {
        case let .device(platform), let .simulator(platform):
            return platform.caseValue
        case .android:
            return "Android"
        }
    }
}
