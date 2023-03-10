import Foundation

/// An enum that represents the type of xcframeworks output
public struct CacheXCFrameworkDestination: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let device = CacheXCFrameworkDestination(rawValue: 1 << 0)
    public static let simulator = CacheXCFrameworkDestination(rawValue: 1 << 1)
    public static let all: CacheXCFrameworkDestination = [.device, .simulator]
}

extension CacheXCFrameworkDestination {
    /// Use to create destination from command textual argument
    public init?(string: String) {
        switch string {
        case "device":
            self = .device
        case "simulator":
            self = .simulator
        case "all":
            self = .all
        default:
            if let int = Int(string) {
                self = .init(rawValue: int)
            } else {
                return nil
            }
        }
    }
}
