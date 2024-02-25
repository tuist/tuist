import Foundation

// MARK: - Configuration

// A the build settings of a target. It is initialized with either the `.debug` or `.release`

public struct Configuration: Equatable, Codable {
    public enum Variant: String, Codable {
        case debug
        case release
    }

    public var name: String
    public var variant: Variant

    public init(
        name: String,
        variant: Configuration.Variant
    ) {
        self.name = name
        self.variant = variant
    }
}

// MARK: - BuildConfiguration

public struct BuildConfiguration: Equatable, Codable, Hashable {
    public enum Variant: String, Codable, Hashable {
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
