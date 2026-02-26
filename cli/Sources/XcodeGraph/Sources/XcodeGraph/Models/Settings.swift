import Foundation
import Path

public typealias SettingsDictionary = [String: SettingValue]

public enum SettingValue: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, Equatable,
    Codable, Sendable
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

public struct Configuration: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public var settings: SettingsDictionary
    public var xcconfig: AbsolutePath?

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

public enum DefaultSettings: Codable, Equatable, Sendable {
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

public struct Settings: Equatable, Codable, Sendable {
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
    public let defaultConfiguration: String?

    // MARK: - Init

    public init(
        base: SettingsDictionary = [:],
        baseDebug: SettingsDictionary = [:],
        configurations: [BuildConfiguration: Configuration?],
        defaultSettings: DefaultSettings = .recommended,
        defaultConfiguration: String? = nil
    ) {
        self.base = base
        self.baseDebug = baseDebug
        self.configurations = configurations
        self.defaultSettings = defaultSettings
        self.defaultConfiguration = defaultConfiguration
    }

    public func with(base: SettingsDictionary) -> Settings {
        .init(
            base: base,
            baseDebug: baseDebug,
            configurations: configurations,
            defaultSettings: defaultSettings,
            defaultConfiguration: defaultConfiguration
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

#if DEBUG
    extension Configuration {
        public static func test(
            settings: SettingsDictionary = [:],
            xcconfig: AbsolutePath? = try! AbsolutePath(validating: "/Config.xcconfig") // swiftlint:disable:this force_try
        ) -> Configuration {
            Configuration(settings: settings, xcconfig: xcconfig)
        }
    }

    extension Settings {
        public static func test(
            base: SettingsDictionary,
            debug: Configuration,
            release: Configuration
        ) -> Settings {
            Settings(
                base: base,
                configurations: [.debug: debug, .release: release]
            )
        }

        public static func test(
            base: SettingsDictionary = [:],
            baseDebug: SettingsDictionary = [:],
            configurations: [BuildConfiguration: Configuration?] = [:]
        ) -> Settings {
            Settings(
                base: base,
                baseDebug: baseDebug,
                configurations: configurations
            )
        }

        public static func test(defaultSettings: DefaultSettings) -> Settings {
            Settings(
                base: [:],
                configurations: [
                    .debug: Configuration(settings: [:]),
                    .release: Configuration(settings: [:]),
                ],
                defaultSettings: defaultSettings
            )
        }
    }
#endif
