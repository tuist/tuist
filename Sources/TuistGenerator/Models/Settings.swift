import Basic
import Foundation
import TuistCore

public class Configuration: Equatable {
    // MARK: - Attributes

    public let settings: [String: String]
    public let xcconfig: AbsolutePath?

    // MARK: - Init

    public init(settings: [String: String] = [:], xcconfig: AbsolutePath? = nil) {
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

    public let base: [String: String]
    public let configurations: [BuildConfiguration: Configuration?]
    public let defaultSettings: DefaultSettings

    // MARK: - Init

    public init(base: [String: String] = [:],
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

extension Dictionary where Key == BuildConfiguration, Value == Configuration? {
    func sortedByBuildConfigurationName() -> [(key: BuildConfiguration, value: Configuration?)] {
        return sorted(by: { first, second -> Bool in first.key.name < second.key.name })
    }

    func xcconfigs() -> [AbsolutePath] {
        return sortedByBuildConfigurationName()
            .map { $0.value }
            .compactMap { $0?.xcconfig }
    }
}
