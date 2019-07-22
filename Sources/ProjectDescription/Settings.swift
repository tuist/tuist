import Foundation

// MARK: - Configuration

public struct Configuration: Equatable, Codable {
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

/// A custom configuration which associats a `BuildConfiguration` and `Configuration`.
///
/// `BuildConfiguration` contains information regarding the configuration name and variant, while
/// the `Configuration` contains the build settings and any associated xcconfig file.
///
public struct CustomConfiguration: Equatable, Codable {
    public let buildConfiguration: BuildConfiguration
    public let configuration: Configuration?

    /// Creates a custom configuration which associated a `BuildConfiguration` and `Configuration`.
    ///
    /// - Parameters:
    ///   - buildConfiguration: The build configuration to use
    ///   - configuration: The configuration to use
    public init(buildConfiguration: BuildConfiguration, configuration: Configuration? = nil) {
        self.buildConfiguration = buildConfiguration
        self.configuration = configuration
    }
}

public extension CustomConfiguration {
    /// Creates a custom debug configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use (defaults to "Debug")
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A debug `CustomConfiguration`
    static func debug(name: String = "Debug", settings: [String: String] = [:], xcconfig: String? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(buildConfiguration: .debug(name: name), configuration: configuration)
    }

    /// Creates a custom release configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use (defaults to "Release")
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A release `CustomConfiguration`
    static func release(name: String = "Release", settings: [String: String] = [:], xcconfig: String? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(buildConfiguration: .release(name: name), configuration: configuration)
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

public struct Settings: Equatable, Codable {
    public let base: [String: String]
    public let configurations: [CustomConfiguration]
    public let defaultSettings: DefaultSettings

    /// Creates settings with the default `Debug` and `Release` configurations.
    ///
    /// - Parameters:
    ///   - base: Base build settings to use
    ///   - debug: The debug configuration
    ///   - release: The release configuration
    ///   - defaultSettings: The default settings to apply during generation
    ///
    /// - Note: To specify additional custom configurations, you can use the alternate initializer `init(base:configurations:defaultSettings:)`.
    ///
    /// - seealso: Configuration
    /// - seealso: DefaultSettings
    public init(base: [String: String] = [:],
                debug: Configuration? = nil,
                release: Configuration? = nil,
                defaultSettings: DefaultSettings = .recommended) {
        configurations = [
            CustomConfiguration(buildConfiguration: .debug, configuration: debug),
            CustomConfiguration(buildConfiguration: .release, configuration: release),
        ]
        self.base = base
        self.defaultSettings = defaultSettings
    }

    /// Creates settings with any number of custom configurations.
    ///
    /// - Parameters:
    ///   - base: Base build settings to use
    ///   - configurations: A list of custom configurations to use
    ///   - defaultSettings: The default settings to apply during generation
    ///
    /// - Note: Configurations shouldn't be empty, please use the alternate initializer `init(base:debug:release:defaultSettings:)`
    ///              to leverage the default configurations if you don't have any custom configurations.
    ///
    /// - seealso: CustomConfiguration
    /// - seealso: DefaultSettings
    public init(base: [String: String] = [:],
                configurations: [CustomConfiguration],
                defaultSettings: DefaultSettings = .recommended) {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }
}
