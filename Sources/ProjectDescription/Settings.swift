import Foundation

// MARK: - Configuration

public class Configuration: Codable {
    public let settings: [String: String]
    public let xcconfig: String?

    public enum CodingKeys: String, CodingKey {
        case settings
        case xcconfig
    }

    public init(settings: [String: String] = [:], xcconfig: String? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    public static func settings(_ settings: [String: String], xcconfig: String? = nil) -> Configuration {
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

// MARK: - Settings

public class Settings: Codable {
    public let base: [String: String]
    public let debug: Configuration?
    public let release: Configuration?

    public init(base: [String: String] = [:],
                debug: Configuration? = nil,
                release: Configuration? = nil) {
        self.base = base
        self.debug = debug
        self.release = release
    }
}
