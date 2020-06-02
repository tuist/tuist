import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// `ContentHashingError`
/// defines all the errors that can happen while cashing the content of a target
enum ContentHashingError: FatalError, Equatable {
    case failedToReadFile(AbsolutePath)
    case fileHashingFailed(AbsolutePath)
    case stringHashingFailed(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .failedToReadFile(path):
            return "Couldn't find file at path \(path.pathString) while hashing the target for caching."
        case let .fileHashingFailed(path):
            return "Couldn't calculate hash of file at path \(path.pathString) for caching."
        case let .stringHashingFailed(string):
            return "Couldn't calculate hash of string \(string) for caching."
        }
    }

    static func == (lhs: ContentHashingError, rhs: ContentHashingError) -> Bool {
        switch (lhs, rhs) {
        case let (.failedToReadFile(lhsPath), .failedToReadFile(rhsPath)):
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
