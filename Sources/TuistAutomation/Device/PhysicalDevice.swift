import Foundation
import XcodeGraph

/// Represents a physical device, such as an iPhone
public struct PhysicalDevice: Codable, Equatable, Identifiable {
    public enum TransportType: String, Codable {
        case wifi
        case usb
    }

    public enum ConnectionState: String, Codable {
        case connected
        case disconnected
    }

    public let id: String
    public let name: String
    public let platform: Platform
    public let osVersion: String?
    public let transportType: TransportType?
    public let connectionState: ConnectionState
}

#if DEBUG
    extension PhysicalDevice {
        public static func test(
            id: String = "id",
            name: String = "My iPhone",
            platform: Platform = .iOS,
            osVersion: String? = "17.4.1",
            transportType: TransportType? = .wifi,
            connectionState: ConnectionState = .connected
        ) -> Self {
            .init(
                id: id,
                name: name,
                platform: platform,
                osVersion: osVersion,
                transportType: transportType,
                connectionState: connectionState
            )
        }
    }
#endif
