import Foundation

/// FileCodeGen: Soure file code generation attribues
public enum FileCodeGen: String, Codable, Equatable {
    /// Public codegen
    case `public`
    /// Private codegen
    case `private`
    /// Project codegen
    case project
    /// Disabled codegen
    case disabled
}
