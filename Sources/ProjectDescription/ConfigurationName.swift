import Foundation

/// `ConfigurationName` is a wrapper around `String` to type the project or workspace configurations.
///
/// The type provides the `.debug` and .release static variables for the `Debug` and `Release` configuration respectively, and we recommend adding new configurations using a extension:
/// ```
/// import ProjectDescription
/// extension ConfigurationName {
///   static var beta: ConfigurationName {
///       ConfigurationName("Beta")
///   }
/// }
/// ```
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

extension ConfigurationName {
    /// Returns a configuration named "Debug"
    public static var debug: ConfigurationName {
        ConfigurationName("Debug")
    }

    // Returns a configuration named "Release"
    public static var release: ConfigurationName {
        ConfigurationName("Release")
    }
}
