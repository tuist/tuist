import Foundation

public typealias SettingsDictionary = [String: SettingValue]

// MARK: - SettingValue

public enum SettingValue: ExpressibleByStringInterpolation, ExpressibleByArrayLiteral, ExpressibleByBooleanLiteral, Equatable, Codable {
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
    public let settings: SettingsDictionary
    public let xcconfig: Path?

    public init(settings: SettingsDictionary = [:], xcconfig: Path? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    public static func settings(_ settings: SettingsDictionary, xcconfig: Path? = nil) -> Configuration {
        Configuration(settings: settings, xcconfig: xcconfig)
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
    static func debug(name: String, settings: SettingsDictionary = [:], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .debug, configuration: configuration)
    }

    /// Creates a custom release configuration
    ///
    /// - Parameters:
    ///   - name: The name of the configuration to use
    ///   - settings: The base build settings to apply
    ///   - xcconfig: The xcconfig file to associate with this configuration
    /// - Returns: A release `CustomConfiguration`
    static func release(name: String, settings: SettingsDictionary = [:], xcconfig: Path? = nil) -> CustomConfiguration {
        let configuration = Configuration(settings: settings, xcconfig: xcconfig)
        return CustomConfiguration(name: name, variant: .release, configuration: configuration)
    }
}

// MARK: - DefaultSettings

/// Specifies the default set of settings applied to all the projects and targets.
/// The default settings can be overridden via `Settings base: SettingsDictionary`
/// and `Configuration settings: SettingsDictionary`.
///
/// - `recommended`: Essential settings plus all the recommended settings (including extra warnings)
/// - essential: Only essential settings to make the projects compile (i.e. `TARGETED_DEVICE_FAMILY`)
public enum DefaultSettings: Codable, Equatable {
    case recommended(excluding: Set<String> = [])
    case essential(excluding: Set<String> = [])
    case none

    enum CodingKeys: CodingKey {
        case recommended, essential, none
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = container.allKeys.first

        switch key {
        case .recommended:
            var nestedContainer = try container.nestedUnkeyedContainer(forKey: .recommended)
            let excludedKeys = try nestedContainer.decode(Set<String>.self)
            self = .recommended(excluding: excludedKeys)
        case .essential:
            var nestedContainer = try container.nestedUnkeyedContainer(forKey: .essential)
            let excludedKeys = try nestedContainer.decode(Set<String>.self)
            self = .essential(excluding: excludedKeys)
        case .none?:
            self = .none
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to decode DefaultSettings. \(String(describing: key)) is an unexpected key. Expected .recommended, .essential or .none."
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .recommended(excludedKeys):
            var nestedContainer = container.nestedUnkeyedContainer(forKey: .recommended)
            try nestedContainer.encode(excludedKeys)
        case let .essential(excludedKeys):
            var nestedContainer = container.nestedUnkeyedContainer(forKey: .essential)
            try nestedContainer.encode(excludedKeys)
        case .none:
            try container.encode(true, forKey: .none)
        }
    }
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

public struct Settings: Equatable, Codable {
    public let base: SettingsDictionary
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
    public init(base: SettingsDictionary = [:],
                debug: Configuration? = nil,
                release: Configuration? = nil,
                defaultSettings: DefaultSettings = .recommended)
    {
        configurations = [
            CustomConfiguration(name: "Debug", variant: .debug, configuration: debug),
            CustomConfiguration(name: "Release", variant: .release, configuration: release),
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
    /// - Note: Configurations shouldn't be empty, please use the alternate initializer
    ///         `init(base:debug:release:defaultSettings:)` to leverage the default configurations
    ///          if you don't have any custom configurations.
    ///
    /// - seealso: CustomConfiguration
    /// - seealso: DefaultSettings
    public init(base: SettingsDictionary = [:],
                configurations: [CustomConfiguration],
                defaultSettings: DefaultSettings = .recommended)
    {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }
}
