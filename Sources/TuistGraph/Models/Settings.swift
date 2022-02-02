import Foundation
import TSCBasic

public typealias SettingsDictionary = [String: SettingValue]

public enum SettingValue: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable, Codable {
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

public struct Configuration: Equatable, Codable {
    // MARK: - Attributes

    public let settings: SettingsDictionary
    public let xcconfig: AbsolutePath?

    // MARK: - Init

    public init(settings: SettingsDictionary = [:], xcconfig: AbsolutePath? = nil) {
        self.settings = settings
        self.xcconfig = xcconfig
    }

    // MARK: - Public

    /// Returns a copy of the configuration with the given settings set.
    /// - Parameter settings: SettingsDictionary to be set to the copy.
    public func with(settings: SettingsDictionary) -> Configuration {
        Configuration(
            settings: settings,
            xcconfig: xcconfig
        )
    }
}

public enum DefaultSettings: Codable, Equatable {
    case recommended(excluding: Set<String> = [])
    case essential(excluding: Set<String> = [])
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

public struct Settings: Equatable, Codable {
    public static let `default` = Settings(
        configurations: [.release: nil, .debug: nil],
        defaultSettings: .recommended
    )

    // MARK: - Attributes

    public let base: SettingsDictionary
    public let configurations: [BuildConfiguration: Configuration?]
    public let defaultSettings: DefaultSettings

    // MARK: - Init

    public init(
        base: SettingsDictionary = [:],
        configurations: [BuildConfiguration: Configuration?],
        defaultSettings: DefaultSettings = .recommended
    ) {
        self.base = base
        self.configurations = configurations
        self.defaultSettings = defaultSettings
    }

    public func with(base: SettingsDictionary) -> Settings {
        .init(
            base: base,
            configurations: configurations,
            defaultSettings: defaultSettings
        )
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
            .map(\.value)
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
