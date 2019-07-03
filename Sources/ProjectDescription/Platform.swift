import Foundation

// MARK: - Platform

public struct Platform: OptionSet, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let iOS = Platform(rawValue: 1 << 0)
    public static let macOS = Platform(rawValue: 1 << 1)
    public static let watchOS = Platform(rawValue: 1 << 2)
    public static let tvOS = Platform(rawValue: 1 << 3)

    public static let all: Platform = [.iOS, .macOS, .watchOS, .tvOS]
}
