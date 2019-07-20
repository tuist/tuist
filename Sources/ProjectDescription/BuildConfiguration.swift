import Foundation

// MARK: - BuildConfiguration

public struct BuildConfiguration: Equatable, Codable {
    public enum Variant: String, Codable {
        case debug, release
    }

    public var name: String
    public var variant: Variant
}

public extension BuildConfiguration {
    static var debug: BuildConfiguration {
        return BuildConfiguration(name: "Debug", variant: .debug)
    }

    static func debug(name: String) -> BuildConfiguration {
        return BuildConfiguration(name: name, variant: .debug)
    }

    static var release: BuildConfiguration {
        return BuildConfiguration(name: "Release", variant: .release)
    }

    static func release(name: String) -> BuildConfiguration {
        return BuildConfiguration(name: name, variant: .release)
    }
}
