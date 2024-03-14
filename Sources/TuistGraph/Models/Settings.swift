import Foundation
import TSCBasic

public typealias SettingsDictionary = [String: SettingValue]

public enum SettingValue: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable,
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

extension SettingsDictionary {
    /// Overlays a SettingsDictionary by adding a `[sdk=<sdk>*]` qualifier
    /// e.g. for a multiplatform target
    ///  `LD_RUNPATH_SEARCH_PATHS = @executable_path/Frameworks`
    ///  `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*] = @executable_path/../Frameworks`
    public mutating func overlay(
        with other: SettingsDictionary,
        for platform: Platform
    ) {
        for (key, newValue) in other {
            if self[key] == nil {
                self[key] = newValue
            } else if self[key] != newValue {
                let newKey = "\(key)[sdk=\(platform.xcodeSdkRoot)*]"
                self[newKey] = newValue
                if platform.hasSimulators, let simulatorSDK = platform.xcodeSimulatorSDK {
                    let newKey = "\(key)[sdk=\(simulatorSDK)*]"
                    self[newKey] = newValue
                }
            }
        }
    }

    /// Combines two `SettingsDictionary`. Instead of overriding values for a duplicate key, it combines them.
    public func combine(with settings: SettingsDictionary) -> SettingsDictionary {
        merging(settings, uniquingKeysWith: { oldValue, newValue in
            let newValues: [String]
            switch newValue {
            case let .string(value):
                newValues = [value]
            case let .array(values):
                newValues = values
            }
            switch oldValue {
            case let .array(values):
                return .array(values + newValues)
            case let .string(value):
                return .array(value.split(separator: " ").map(String.init) + newValues)
            }
        })
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
    /// Base settings applied only for configurations of `variant == .debug`
    public let baseDebug: SettingsDictionary
    public let configurations: [BuildConfiguration: Configuration?]
    public let defaultSettings: DefaultSettings

    // MARK: - Init

    public init(
        base: SettingsDictionary = [:],
        baseDebug: SettingsDictionary = [:],
        configurations: [BuildConfiguration: Configuration?],
        defaultSettings: DefaultSettings = .recommended
    ) {
        self.base = base
        self.baseDebug = baseDebug
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

extension [BuildConfiguration: Configuration?] {
    public func sortedByBuildConfigurationName() -> [(key: BuildConfiguration, value: Configuration?)] {
        sorted(by: { first, second -> Bool in first.key < second.key })
    }

    public func xcconfigs() -> [AbsolutePath] {
        sortedByBuildConfigurationName()
            .map(\.value)
            .compactMap { $0?.xcconfig }
    }
}

extension [String: SettingValue] {
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
