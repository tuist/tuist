import Basic
import Foundation
import TuistCore
import TuistSupport

enum ContentHashingError: FatalError, Equatable {
    case fileNotFound(AbsolutePath)
    case fileHashingFailed(AbsolutePath)
    case stringHashingFailed(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "Couldn't find file at path \(path.pathString) while hashing the target for caching."
        case let .fileHashingFailed(path):
            return "Couldn't calculate hash of file at path \(path.pathString) for caching."
        case let .stringHashingFailed(string):
            return "Couldn't calculate hash of string \(string) for caching."
        }
    }

    static func == (lhs: ContentHashingError, rhs: ContentHashingError) -> Bool {
        switch (lhs, rhs) {
        case let (.fileNotFound(lhsPath), .fileNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.fileHashingFailed(lhsPath), .fileHashingFailed(rhsPath)):
            return lhsPath == rhsPath
        case let (.stringHashingFailed(lhsPath), .stringHashingFailed(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}
