import Foundation

// MARK: - DeploymentDevice

public struct DeploymentDevice: OptionSet, Codable, Hashable {
    public static let iphone = DeploymentDevice(rawValue: 1 << 0)
    public static let ipad = DeploymentDevice(rawValue: 1 << 1)
    public static let mac = DeploymentDevice(rawValue: 1 << 2)

    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    // All deployment devices.
    public static var all: DeploymentDevice {
        [.iphone, .ipad, .mac]
    }
}
