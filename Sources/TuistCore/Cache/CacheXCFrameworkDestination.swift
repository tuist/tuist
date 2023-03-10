import Foundation

/// An enum that represents the type of xcframeworks output
public struct CacheXCFrameworkDestination: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let device = CacheXCFrameworkDestination(rawValue: 1 << 0)
    public static let simulator = CacheXCFrameworkDestination(rawValue: 1 << 1)
}
