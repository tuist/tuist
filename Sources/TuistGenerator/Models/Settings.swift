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

    // MARK: - Internal

    static func ordered(configurations: [BuildConfiguration: Configuration?])
        -> [(key: BuildConfiguration, value: Configuration?)] {
        return configurations.sorted(by: { first, second -> Bool in
            first.key.name < second.key.name
        })
    }

    func orderedConfigurations() -> [(key: BuildConfiguration, value: Configuration?)] {
        return Settings.ordered(configurations: configurations)
    }

    func xcconfigs() -> [AbsolutePath] {
        return orderedConfigurations()
            .map { $0.value }
            .compactMap { $0?.xcconfig }
    }

    // MARK: - Equatable

    public static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.base == rhs.base && lhs.configurations == rhs.configurations
    }
}
