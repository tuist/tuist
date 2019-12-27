import Basic
import Foundation

protocol ModelConvertible {
    associatedtype T

//    /// Initializes the struct or class that conforms this protocol from its equivalent representation
//    /// in the project description domain.
//    /// - Parameters:
//    ///   - manifest: Manifest reprepsentation of the model being initialized.
//    ///   - path: Path to the directory that contains the manifest definition.
//    static func from(manifest: T, path: AbsolutePath) throws -> Self
//
//
    init(manifest: T, path: AbsolutePath) throws
}
