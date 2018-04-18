import Basic
import Foundation

enum GraphLoadingError: Error, Equatable {
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
}
