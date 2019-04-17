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

public class Settings: Equatable {
    public static let `default` = Settings(configurations: [.release: nil, .debug: nil])

    // MARK: - Attributes

    public let base: [String: String]
    public let configurations: [BuildConfiguration: Configuration?]

    // MARK: - Init

    public init(base: [String: String] = [:],
                configurations: [BuildConfiguration: Configuration?]) {
        self.base = base
        self.configurations = configurations
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
