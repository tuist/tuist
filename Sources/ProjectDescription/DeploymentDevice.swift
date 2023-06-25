import Foundation

// MARK: - DeploymentDevice

/// A supported deployment device.
public struct DeploymentDevice: OptionSet, Codable, Hashable {
    /// An iPhone device.
    public static let iphone = DeploymentDevice(rawValue: 1 << 0)
    /// An iPad device.
    public static let ipad = DeploymentDevice(rawValue: 1 << 1)
    /// A Mac device.
    public static let mac = DeploymentDevice(rawValue: 1 << 2)
    /// An Apple Vision device.
    public static let vision = DeploymentDevice(rawValue: iphone.rawValue | ipad.rawValue | mac.rawValue)

    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}
