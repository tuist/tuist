import Basic
import Foundation
import TuistSupport

public enum SettingValue: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable, Hashable {
    case string(String)
    case array([String])

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(arrayLiteral elements: String...) {
        self = .array(elements)
    }

    public func normalize() -> SettingValue {
        switch self {
        case let .array(currentValue):
            if currentValue.count == 1 {
                return .string(currentValue[0])
            }
            return self
        case .string:
            return self
        }
    }    
}

public class Configuration: Equatable, Hashable {
    // MARK: - Attributes

    public let settings: [String: SettingValue]
    public let xcconfig: AbsolutePath?

    // MARK: - Init

    public init(settings: [String: SettingValue] = [:], xcconfig: AbsolutePath? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    // MARK: - Equatable

    public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        lhs.settings == rhs.settings && lhs.xcconfig == rhs.xcconfig
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(xcconfig?.pathString)
        hasher.combine(settings)
    }
}

public enum DefaultSettings: Hashable {
    case recommended
    case essential
    case none
}

public class Settings: Equatable, Hashable {
    public static let `default` = Settings(configurations: [.release: nil, .debug: nil],
                                           defaultSettings: .recommended)

    // MARK: - Attributes

    public let base: [String: SettingValue]
    public let configurations: [BuildConfiguration: Configuration?]
    public let defaultSettings: DefaultSettings

    // MARK: - Init

    public init(base: [String: SettingValue] = [:],
                configurations: [BuildConfiguration: Configuration?],
                defaultSettings: DefaultSettings = .recommended) {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }

    // MARK: - Equatable

    public static func == (lhs: Settings, rhs: Settings) -> Bool {
        lhs.base == rhs.base && lhs.configurations == rhs.configurations
    }
    
    // MARK: - Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(configurations)
        hasher.combine(defaultSettings)
    }
}

extension Settings {
    /// Finds the default debug `BuildConfiguration` if it exists, otherwise returns the first debug configuration available.
    ///
    /// - Returns: The default debug `BuildConfiguration`
    public func defaultDebugBuildConfiguration() -> BuildConfiguration? {
        let debugConfigurations = configurations.keys
            .filter { $0.variant == .debug }
            .sorted()
        let defaultConfiguration = debugConfigurations.first(where: { $0 == BuildConfiguration.debug })
        return defaultConfiguration ?? debugConfigurations.first
    }

    /// Finds the default release `BuildConfiguration` if it exists, otherwise returns the first release configuration available.
    ///
    /// - Returns: The default release `BuildConfiguration`
    public func defaultReleaseBuildConfiguration() -> BuildConfiguration? {
        let releaseConfigurations = configurations.keys
            .filter { $0.variant == .release }
            .sorted()
        let defaultConfiguration = releaseConfigurations.first(where: { $0 == BuildConfiguration.release })
        return defaultConfiguration ?? releaseConfigurations.first
    }
}

extension Dictionary where Key == BuildConfiguration, Value == Configuration? {
    public func sortedByBuildConfigurationName() -> [(key: BuildConfiguration, value: Configuration?)] {
        sorted(by: { first, second -> Bool in first.key < second.key })
    }

    public func xcconfigs() -> [AbsolutePath] {
        sortedByBuildConfigurationName()
            .map { $0.value }
            .compactMap { $0?.xcconfig }
    }
}

extension Dictionary where Key == String, Value == SettingValue {
    public func toAny() -> [String: Any] {
        mapValues { value in
            switch value {
            case let .array(array):
                return array
            case let .string(string):
                return string
            }
        }
    }
}
