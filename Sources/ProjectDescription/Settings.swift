import Foundation

// MARK: - SettingValue

public enum SettingValue: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable, Codable {
    case string(String)
    case array([String])

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(arrayLiteral elements: String...) {
        self = .array(elements)
    }

    public init(from decoder: Decoder) throws {
        guard let singleValueContainer = try? decoder.singleValueContainer() else {
            preconditionFailure("Unsupported container type")
        }
        if let value: String = try? singleValueContainer.decode(String.self) {
            self = .string(value)
            return
        }
        if let value: [String] = try? singleValueContainer.decode([String].self) {
            self = .array(value)
            return
        }

        fatalError("Unsupported encoded type")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        }
    }
}

// MARK: - Configuration

public struct Configuration: Equatable, Codable {
    public let settings: [String: SettingValue]
    public let xcconfig: Path?

    public init(settings: [String: SettingValue] = [:], xcconfig: Path? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    @available(*, deprecated, message: "Please use init(settings: [String: SettingValue], xcconfig: String?) instead")
    public init(settings: [String: String], xcconfig: Path? = nil) {
        self.settings = settings.mapValues { .string($0) }
        self.xcconfig = xcconfig
    }

    public static func settings(_ settings: [String: SettingValue], xcconfig: Path? = nil) -> Configuration {
        return Configuration(settings: settings, xcconfig: xcconfig)
    }

    @available(*, deprecated, message: "Please use settings(_ settings: [String: SettingValue], xcconfig: String?)")
    public static func settings(_ settings: [String: String], xcconfig: Path? = nil) -> Configuration {
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

/// A custom configuration allows declaring a named build configuration along with its settings.
///
/// Additionally, a custom configuration specifies the configuration variant (debug or release)
/// to help Tuist select the most appropriate default settings.
///
/// - seealso: Configuration
public struct CustomConfiguration: Equatable, Codable {
    public enum Variant: String, Codable {
        case debug
        case release
    }

    public let name: String
    public let variant: Variant
    public let configuration: Configuration?

    init(name: String, variant: Variant, configuration: Configuration? = nil) {
        self.name = name
        self.variant = variant
        self.configuration = configuration
    }
}

public extension CustomConfiguration {
    /// Creates a custom debug configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A debug `CustomConfiguration`
    static func debug(name: String, settings: [String: SettingValue] = [:], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .debug, configuration: configuration)
    }

    @available(*, deprecated, message: "Please use debug(name: String, settings: [String: SettingValue], xcconfig: String?) instead")
    static func debug(name: String, settings: [String: String], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings.mapValues { .string($0) }, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .debug, configuration: configuration)
    }

    /// Creates a custom release configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A release `CustomConfiguration`
    static func release(name: String, settings: [String: SettingValue] = [:], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .release, configuration: configuration)
    }

    @available(*, deprecated, message: "Please use release(name: String, settings: [String: SettingValue], xcconfig: String?) instead")
    static func release(name: String, settings: [String: String], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings.mapValues { .string($0) }, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .release, configuration: configuration)
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
    case none
}

// MARK: - Settings

public struct Settings: Equatable, Codable {
    public let base: [String: SettingValue]
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
    /// - Note: To specify additional custom configurations, you can use the
    ///         alternate initializer `init(base:configurations:defaultSettings:)`.
    ///
    /// - seealso: Configuration
    /// - seealso: DefaultSettings
    public init(base: [String: SettingValue] = [:],
                debug: Configuration? = nil,
                release: Configuration? = nil,
                defaultSettings: DefaultSettings = .recommended) {
        configurations = [
            CustomConfiguration(name: "Debug", variant: .debug, configuration: debug),
            CustomConfiguration(name: "Release", variant: .release, configuration: release),
        ]
        self.base = base
        self.defaultSettings = defaultSettings
    }

    // swiftlint:disable:next line_length
    @available(*, deprecated, message: "Please use init(base: [String: SettingValue], debug: Configuration?, release: Configuration?, defaultSettings: DefaultSettings) instead")
    public init(base: [String: String],
                debug: Configuration? = nil,
                release: Configuration? = nil,
                defaultSettings: DefaultSettings = .recommended) {
        configurations = [
            CustomConfiguration(name: "Debug", variant: .debug, configuration: debug),
            CustomConfiguration(name: "Release", variant: .release, configuration: release),
        ]
        self.base = base.mapValues { .string($0) }
        self.defaultSettings = defaultSettings
    }

    /// Creates settings with any number of custom configurations.
    ///
    /// - Parameters:
    ///   - base: Base build settings to use
    ///   - configurations: A list of custom configurations to use
    ///   - defaultSettings: The default settings to apply during generation
    ///
    /// - Note: Configurations shouldn't be empty, please use the alternate initializer
    ///         `init(base:debug:release:defaultSettings:)` to leverage the default configurations
    ///          if you don't have any custom configurations.
    ///
    /// - seealso: CustomConfiguration
    /// - seealso: DefaultSettings
    public init(base: [String: SettingValue] = [:],
                configurations: [CustomConfiguration],
                defaultSettings: DefaultSettings = .recommended) {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }

    // swiftlint:disable:next line_length
    @available(*, deprecated, message: "Please use init(base: [String: SettingValue], configurations: [CustomConfiguration], defaultSettings: DefaultSettings) instead")
    public init(base: [String: String],
                configurations: [CustomConfiguration],
                defaultSettings: DefaultSettings = .recommended) {
        self.base = base.mapValues { .string($0) }
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }
}
