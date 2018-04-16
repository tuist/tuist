import Foundation

// MARK: - Settings

public class Settings {
    public class Configuration {
        public let settings: [String: String]
        public let xcconfig: String?
        public init(settings: [String: String] = [:], xcconfig: String? = nil) {
            self.settings = settings
            self.xcconfig = xcconfig
        }

        public static func settings(_ settings: [String: String], xcconfig: String? = nil) -> Configuration {
            return Configuration(settings: settings, xcconfig: xcconfig)
        }
    }

    public let base: [String: String]
    public let debug: Configuration?
    public let release: Configuration?

    public init(base: [String: String] = [:],
                debug: Configuration?,
                release: Configuration?) {
        self.base = base
        self.debug = debug
        self.release = release
    }
}

// MARK: - Settings (JSONConvertible)

extension Settings: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["base"] = base.toJSON()
        if let debug = debug {
            dictionary["debug"] = debug.toJSON()
        }
        if let release = release {
            dictionary["release"] = release.toJSON()
        }
        return .dictionary(dictionary)
    }
}

extension Settings.Configuration: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        if let xcconfig = xcconfig {
            dictionary["xcconfig"] = xcconfig.toJSON()
        }
        dictionary["settings"] = settings.toJSON()
        return .dictionary(dictionary)
    }
}
