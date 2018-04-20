import Basic
import Foundation

/// Errors that can be thrown during the graph loading process.
///
/// - missingFile: error thrown when a manifest is refering to a file that is missing.
/// - targetNotFound: error thrown when a target has a dependency with another target that doesn't exist.
/// - manifestNotFound: error thrown when a manifest cannot be found.
/// - unexpected: unexpected error.
enum GraphLoadingError: Error, Equatable, CustomStringConvertible {
    case missingFile(AbsolutePath)
    case targetNotFound(String, AbsolutePath)
    case manifestNotFound(AbsolutePath)
    case unexpected(String)

    /// Compares two GraphLoadingError instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: GraphLoadingError, rhs: GraphLoadingError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFile(lhsPath), .missingFile(rhsPath)):
            return lhsPath == rhsPath
        case let (.targetNotFound(lhsName, lhsPath), .targetNotFound(rhsName, rhsPath)):
            return lhsPath == rhsPath && lhsName == rhsName
        case let (.manifestNotFound(lhsPath), .manifestNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.unexpected(lhsMessage), .unexpected(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find manifest at path: '\(path.asString)'"
        case let .targetNotFound(targetName, path):
            return "Couldn't find target '\(targetName)' at '\(path.asString)'"
        case let .missingFile(path):
            return "Couldn't find file at path '\(path.asString)'"
        case let .unexpected(message):
            return message
        }
    }
}
