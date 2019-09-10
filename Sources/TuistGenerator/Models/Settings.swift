import Basic
import Foundation
import TuistCore

public enum SettingValue: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable {
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

public class Configuration: Equatable {
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
        return lhs.settings == rhs.settings && lhs.xcconfig == rhs.xcconfig
    }
}

public enum DefaultSettings {
    case recommended
    case essential
    case none
}

public class Settings: Equatable {
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
        return lhs.base == rhs.base && lhs.configurations == rhs.configurations
    }
}

extension Settings {
    /// Finds the default debug `BuildConfiguration` if it exists, otherwise returns the first debug configuration available.
    ///
    /// - Returns: The default debug `BuildConfiguration`
    func defaultDebugBuildConfiguration() -> BuildConfiguration? {
        let debugConfigurations = configurations.keys
            .filter { $0.variant == .debug }
            .sorted()
        let defaultConfiguration = debugConfigurations.first(where: { $0 == BuildConfiguration.debug })
        return defaultConfiguration ?? debugConfigurations.first
    }

    /// Finds the default release `BuildConfiguration` if it exists, otherwise returns the first release configuration available.
    ///
    /// - Returns: The default release `BuildConfiguration`
    func defaultReleaseBuildConfiguration() -> BuildConfiguration? {
        let releaseConfigurations = configurations.keys
            .filter { $0.variant == .release }
            .sorted()
        let defaultConfiguration = releaseConfigurations.first(where: { $0 == BuildConfiguration.release })
        return defaultConfiguration ?? releaseConfigurations.first
    }
}

extension Dictionary where Key == BuildConfiguration, Value == Configuration? {
    func sortedByBuildConfigurationName() -> [(key: BuildConfiguration, value: Configuration?)] {
        return sorted(by: { first, second -> Bool in first.key < second.key })
    }

    func xcconfigs() -> [AbsolutePath] {
        return sortedByBuildConfigurationName()
            .map { $0.value }
            .compactMap { $0?.xcconfig }
    }
}

extension Dictionary where Key == String, Value == SettingValue {
    func toAny() -> [String: Any] {
        return mapValues { value in
            switch value {
            case let .array(array):
                return array
            case let .string(string):
                return string
            }
        }
    }
}
