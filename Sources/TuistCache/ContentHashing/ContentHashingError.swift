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
    case dataHashingFailed

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .failedToReadFile(path):
            return "Couldn't find file to calculate hash at path \(path.pathString)"
        case let .fileHashingFailed(path):
            return "Couldn't calculate hash of file at path \(path.pathString)"
        case let .stringHashingFailed(string):
            return "Couldn't calculate hash of string \(string) for caching."
        case .dataHashingFailed:
            return "Couldn't calculate the hash of a data object."
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
        case (.dataHashingFailed, .dataHashingFailed):
            return true
        default:
            return false
        }
    }
}
