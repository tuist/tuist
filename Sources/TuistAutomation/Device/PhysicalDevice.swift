import Foundation
import XcodeGraph

/// Represents a physical device, such as an iPhone
public struct PhysicalDevice: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let platform: Platform
    public let osVersion: String?
}

#if DEBUG
    extension PhysicalDevice {
        public static func test(
            id: String = "id",
            name: String = "My iPhone",
            platform: Platform = .iOS,
            osVersion: String? = "17.4.1"
        ) -> Self {
            .init(
                id: id,
                name: name,
                platform: platform,
                osVersion: osVersion
            )
        }
    }
#endif
