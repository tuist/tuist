import Foundation

// MARK: - Configuration

// A the build Configuration of a target.

public struct Configuration: Equatable, Codable, Sendable {
    let settings: SettingsDictionary

    public init(
        settings: SettingsDictionary
    ) {
        self.settings = settings
    }
}

// MARK: - BuildConfiguration

public struct BuildConfiguration: Equatable, Codable, Hashable, Sendable {
    public enum Variant: String, Codable, Hashable, Sendable {
        case debug
        case release
    }

    public var name: String
    public var variant: BuildConfiguration.Variant

    public init(
        name: String,
        variant: BuildConfiguration.Variant
    ) {
        self.name = name
        self.variant = variant
    }
}

public typealias SettingsDictionary = [String: SettingValue]

public enum SettingValue: Equatable, Codable, Sendable {
    case string(value: String)
    case array(value: [String])

    public init(string: String) {
        self = .string(value: string)
    }

    public init(array: [String]) {
        self = .array(value: array)
    }
}
