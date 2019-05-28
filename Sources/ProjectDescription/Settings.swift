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

// MARK: - DefaultSettings

/// Specifies the default set of settings applied to all the projects and targets.
/// The default settings can be overridden via `Settings base: [String: String]`
/// and `Configuration settings: [String: String]`.
///
/// - all: Essential settings plus all the recommended settings (including extra warnings)
/// - essential: Only essential settings to make the projects compile (i.e. `TARGETED_DEVICE_FAMILY`)
public enum DefaultSettings: String, Codable {
    case recommended
    case essential
}

// MARK: - Settings

public class Settings: Codable {
    public let base: [String: String]
    public let debug: Configuration?
    public let release: Configuration?
    public let defaultSettings: DefaultSettings

    public init(base: [String: String] = [:],
                debug: Configuration? = nil,
                release: Configuration? = nil,
                defaultSettings: DefaultSettings = .recommended) {
        self.base = base
        self.debug = debug
        self.release = release
        self.defaultSettings = defaultSettings
    }
}
