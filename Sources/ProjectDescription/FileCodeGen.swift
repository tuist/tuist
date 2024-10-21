import Foundation

/// Options for source file code generation.
public enum FileCodeGen: String, Codable, Equatable, Sendable {
    /// Public codegen
    case `public`
    /// Private codegen
    case `private`
    /// Project codegen
    case project
    /// Disabled codegen
    case disabled
}
