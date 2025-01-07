import Foundation

// MARK: - Configuration

// The build Configuration of a target.

public struct Configuration: Equatable, Codable {
    private let settings: SettingsDictionary

    public init(
        settings: SettingsDictionary
    ) {
        self.settings = settings
    }
}

// MARK: - BuildConfiguration

public struct BuildConfiguration: Codable, Hashable {
    public enum Variant: Codable {
        case debug
        case release
    }

    private let name: String
    private let variant: Variant

    public init(name: String, variant: Variant) {
        self.name = name
        self.variant = variant
    }
}

public typealias SettingsDictionary = [String: SettingValue]

public enum SettingValue: Equatable, Codable {
    case string(value: String)
    case array(value: [String])

    public init(string: String) {
        self = .string(value: string)
    }

    public init(array: [String]) {
        self = .array(value: array)
    }
}
