import Basic
import Foundation

enum GraphLoadingError: Error, Equatable, CustomStringConvertible {
    case missingFile(AbsolutePath)
    case targetNotFound(String, AbsolutePath)
    case manifestNotFound(AbsolutePath)
    case unexpected(String)

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
            return "Couldn't find manifest at path: '\(path)'"
        case let .targetNotFound(targetName, path):
            return "Couldn't find target '\(targetName)' at '\(path)'"
        case let .missingFile(path):
            return "Couldn't find file at path '\(path)'"
        case let .unexpected(message):
            return message
        }
    }
}
