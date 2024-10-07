import Foundation
import XcodeGraph

/// Represents a destination type either for a simulator or a device with a given platform.
public enum DestinationType: Codable, Equatable {
    case simulator(Platform)
    case device(Platform)

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
        }
    }
}
