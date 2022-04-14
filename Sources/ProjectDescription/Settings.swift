import Foundation

public typealias SettingsDictionary = [String: SettingValue]

/// A value or a collection of values used for settings configuration.
public enum SettingValue: ExpressibleByStringInterpolation, ExpressibleByArrayLiteral, ExpressibleByBooleanLiteral, Equatable,
    Codable
{
    case string(String)
    case array([String])

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(arrayLiteral elements: String...) {
        self = .array(elements)
    }

    public typealias BooleanLiteralType = Bool

    public init(booleanLiteral value: Bool) {
        self = .string(value ? "YES" : "NO")
    }

    public init<T>(_ stringRawRepresentable: T) where T: RawRepresentable, T.RawValue == String {
        self = .init(stringLiteral: stringRawRepresentable.rawValue)
    }
}

// MARK: - Configuration

/// A the build settings and the .xcconfig file of a project or target. It is initialized with either the `.debug` or `.release` static method.
public struct Configuration: Equatable, Codable {
    public enum Variant: String, Codable {
        case debug
        case release
    }

    public let name: ConfigurationName
    public let variant: Variant
    public let settings: SettingsDictionary
    public let xcconfig: Path?

    init(name: ConfigurationName, variant: Variant, settings: SettingsDictionary, xcconfig: Path?) {
        self.name = name
        self.variant = variant
        self.settings = settings
        self.xcconfig = xcconfig
    }

    /// Returns a debug configuration.
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A debug `CustomConfiguration`
    public static func debug(
        name: ConfigurationName,
        settings: SettingsDictionary = [:],
        xcconfig: Path? = nil
    ) -> Configuration {
        Configuration(
            name: name,
            variant: .debug,
            settings: settings,
            xcconfig: xcconfig
        )
    }

    /// Creates a release configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A release `CustomConfiguration`
    public static func release(
        name: ConfigurationName,
        settings: SettingsDictionary = [:],
        xcconfig: Path? = nil
    ) -> Configuration {
        Configuration(
            name: name,
            variant: .release,
            settings: settings,
            xcconfig: xcconfig
        )
    }
}

// MARK: - DefaultSettings

/// Specifies the default set of settings applied to all the projects and targets.
/// The default settings can be overridden via `Settings base: SettingsDictionary`
/// and `Configuration settings: SettingsDictionary`.
public enum DefaultSettings: Codable, Equatable {
    /// Recommended settings including warning flags to help you catch some of the bugs at the early stage of development. If you need to override certain settings in a `Configuration` it's possible to add those keys to `excluding`.
    case recommended(excluding: Set<String> = [])
    /// A minimal set of settings to make the project compile without any additional settings for example `PRODUCT_NAME` or `TARGETED_DEVICE_FAMILY`. If you need to override certain settings in a Configuration it's possible to add those keys to `excluding`.
    case essential(excluding: Set<String> = [])
    /// Tuist won't generate any build settings for the target or project.
    case none
}

extension DefaultSettings {
    public static var recommended: DefaultSettings {
        .recommended(excluding: [])
    }

    public static var essential: DefaultSettings {
        .essential(excluding: [])
    }
}

// MARK: - Settings

/// A group of settings configuration.
public struct Settings: Equatable, Codable {
    /// A dictionary with build settings that are inherited from all the configurations.
    public let base: SettingsDictionary
    public let configurations: [Configuration]
    public let defaultSettings: DefaultSettings

    init(
        base: SettingsDictionary,
        configurations: [Configuration],
        defaultSettings: DefaultSettings
    ) {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }

    /// Creates settings with default.configurations `Debug` and `Release`
    ///
    /// - Parameters:
    ///   - base: A dictionary with build settings that are inherited from all the configurations.
    ///   - debug: The debug configuration settings.
    ///   - release: The release configuration settings.
    ///   - defaultSettings: An enum specifying the set of default settings.
    ///
    /// - Note: To specify custom configurations (e.g. `Debug`, `Beta` & `Release`) or to specify xcconfigs, you can use the alternate static method
    ///         `.settings(base:configurations:defaultSettings:)`
    ///
    /// - seealso: Configuration
    /// - seealso: DefaultSettings
    public static func settings(
        base: SettingsDictionary = [:],
        debug: SettingsDictionary = [:],
        release: SettingsDictionary = [:],
        defaultSettings: DefaultSettings = .recommended
    ) -> Settings {
        Settings(
            base: base,
            configurations: [
                .debug(name: .debug, settings: debug, xcconfig: nil),
                .release(name: .release, settings: release, xcconfig: nil),
            ],
            defaultSettings: defaultSettings
        )
    }

    /// Creates settings with any number of configurations.
    ///
    /// - Parameters:
    ///   - base: A dictionary with build settings that are inherited from all the configurations.
    ///   - configurations: A list of configurations.
    ///   - defaultSettings: An enum specifying the set of default settings.
    ///
    /// - Note: Configurations shouldn't be empty, please use the alternate static method
    ///         `.settings(base:debug:release:defaultSettings:)` to leverage the default configurations
    ///          if you don't have any custom configurations.
    ///
    /// - seealso: Configuration
    /// - seealso: DefaultSettings
    public static func settings(
        base: SettingsDictionary = [:],
        configurations: [Configuration],
        defaultSettings: DefaultSettings = .recommended
    ) -> Settings {
        Settings(
            base: base,
            configurations: configurations,
            defaultSettings: defaultSettings
        )
    }
}
