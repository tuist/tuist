import Foundation

// MARK: - Configuration

public typealias BuildSettings = [String: String]

public class Configuration: Codable {
    
    public typealias Name = String
    
    public let name: Name
    public let settings: BuildSettings
    public let xcconfig: String?
    public let buildConfiguration: BuildConfiguration

    public enum CodingKeys: String, CodingKey {
        case name
        case settings
        case xcconfig
        case buildConfiguration
    }

    public init(name: String, settings: BuildSettings = [:], xcconfig: String? = nil, buildConfiguration: BuildConfiguration) {
        self.name = name
        self.settings = settings
        self.xcconfig = xcconfig
        self.buildConfiguration = buildConfiguration
    }

    public static func debug(name: String = "Debug", settings: BuildSettings = [:], xcconfig: String? = nil) -> Configuration {
        return Configuration(name: name, settings: settings, xcconfig: xcconfig, buildConfiguration: .debug)
    }
    
    public static func release(name: String = "Release", settings: BuildSettings = [:], xcconfig: String? = nil) -> Configuration {
        return Configuration(name: name, settings: settings, xcconfig: xcconfig, buildConfiguration: .release)
    }
    
}

// MARK: - Settings

public class Settings: Codable {
    
    public let base: BuildSettings
    public let configurations: [Configuration]

    public init(base: BuildSettings = [:], configurations: [Configuration] = []) {
        self.base = base
        self.configurations = configurations
    }
    
}
