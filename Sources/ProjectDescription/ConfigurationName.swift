import Foundation

/// It represent's a project configuration.
public struct ConfigurationName: ExpressibleByStringLiteral, Codable, Equatable {
    /// Configuration name.
    public let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Initializes a configuration name with its name.
    /// - Parameter value: Configuration name.
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    /// Initializes a configuration name with its name.
    /// - Parameter name: Configuration name.
    /// - Returns: Initialized configuration name.
    public static func configuration(_ name: String) -> ConfigurationName {
        self.init(name)
    }
}

// Defaults provided by Tuist

public extension ConfigurationName {
    /// Returns a configuration named "Debug"
    static var debug: ConfigurationName {
        ConfigurationName("Debug")
    }

    // Returns a configuration named "Release"
    static var release: ConfigurationName {
        ConfigurationName("Release")
    }
}
