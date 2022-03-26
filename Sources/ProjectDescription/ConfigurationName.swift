import Foundation

/// A configuration name.
///
/// It has build-in support for ``debug`` and ``release`` configurations.
///
/// You can extend with your own configurations using a extension:
/// ```
/// import ProjectDescription
/// extension ConfigurationName {
///   static var beta: ConfigurationName {
///       ConfigurationName("Beta")
///   }
/// }
/// ```
public struct ConfigurationName: ExpressibleByStringLiteral, Codable, Equatable {
    /// The configuration name.
    public let rawValue: String

    internal init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a configuration name with its name.
    /// - Parameter value: Configuration name.
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    /// Returns a configuration name with its name.
    /// - Parameter name: Configuration name.
    /// - Returns: Initialized configuration name.
    public static func configuration(_ name: String) -> ConfigurationName {
        self.init(name)
    }

    /// Returns a configuration named "Debug"
    public static var debug: ConfigurationName {
        ConfigurationName("Debug")
    }

    /// Returns a configuration named "Release"
    public static var release: ConfigurationName {
        ConfigurationName("Release")
    }
}
