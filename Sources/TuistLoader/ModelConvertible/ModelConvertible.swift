import Basic
import Foundation

protocol ModelConvertible {
    associatedtype T

    /// Initializes the struct or class conforming this protocol from its equivalent representation
    /// in the project description domain.
    /// - Parameters:
    ///   - manifest: Manifest representation of the model being initialized.
    ///   - generatorPaths: Instance to resolve relative paths.
    init(manifest: T, generatorPaths: GeneratorPaths) throws
}
