import Basic
import Foundation
import TuistCore

typealias BuildSettings = [String: String]

class Configuration: Equatable {
    
    typealias Name = String
    // MARK: - Attributes

    let name: String
    let buildConfiguration: BuildConfiguration
    let settings: BuildSettings
    let xcconfig: AbsolutePath?

    // MARK: - Init

    init(name: String, buildConfiguration: BuildConfiguration, settings: BuildSettings = [:], xcconfig: AbsolutePath? = nil) {
        self.name = name
        self.buildConfiguration = buildConfiguration
        self.settings = settings
        self.xcconfig = xcconfig
    }

    // MARK: - Equatable

    static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        return lhs.name == rhs.name &&
            lhs.buildConfiguration == rhs.buildConfiguration &&
            lhs.settings == rhs.settings &&
            lhs.xcconfig == rhs.xcconfig
    }
}

class Settings: Equatable {
    // MARK: - Attributes

    let base: BuildSettings
    let configurations: [Configuration]

    // MARK: - Init

    init(base: BuildSettings = [:], configurations: [Configuration]) {
        self.base = base
        self.configurations = configurations
    }
    
    // MARK: - Equatable

    static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.base == rhs.base && lhs.configurations == rhs.configurations
    }
}
