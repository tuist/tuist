import Foundation
import XcodeGraph

/// Represents a platform either for a simulator or a device
public enum DestinationPlatform: Codable, Equatable {
    case simulator(Platform)
    case device(Platform)
}

extension DestinationPlatform {
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
