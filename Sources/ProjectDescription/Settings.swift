import Foundation

// MARK: - Configuration

public class Configuration: Codable {
    public let name: String
    public let type: BuildConfiguration
    public let settings: [String: String]
    public let xcconfig: String?

    public enum CodingKeys: String, CodingKey {
        case name
        case type
        case settings
        case xcconfig
    }

    public init(name: String, type: BuildConfiguration, settings: [String: String] = [:], xcconfig: String? = nil) {
        self.name = name
        self.type = type
        self.settings = settings
        self.xcconfig = xcconfig
    }

    public static func debug(_ settings: [String: String] = [:], xcconfig: String? = nil) -> Configuration {
        return Configuration(name: "Debug", type: .debug, settings: settings, xcconfig: xcconfig)
    }
    
    public static func release(_ settings: [String: String] = [:], xcconfig: String? = nil) -> Configuration {
        return Configuration(name: "Release", type: .release, settings: settings, xcconfig: xcconfig)
    }
    
    public static func configuration(name: String, type: BuildConfiguration = .debug, settings: [String: String] = [:], xcconfig: String? = nil) -> Configuration {
        return Configuration(name: name, type: type, settings: settings, xcconfig: xcconfig)
    }
    
}

// MARK: - Settings

public class Settings: Codable {
    public let base: [String: String]
    public let configurations: [Configuration]

    public init(base: [String: String] = [:], debug: Configuration = .debug(), release: Configuration = .release()) {
        self.base = base
        self.configurations = [ debug, release ]
    }
    
    public init(base: [String: String] = [:], configurations: [Configuration]) {
        self.base = base
        self.configurations = configurations
    }
    
}
