import Foundation
import TSCBasic
import TuistSupport

/// `ContentHashingError`
/// defines all the errors that can happen while cashing the content of a target
public enum ContentHashingError: FatalError, Equatable {
    case failedToReadFile(AbsolutePath)
    case fileHashingFailed(AbsolutePath)
    case stringHashingFailed(String)
    case dataHashingFailed

    public var type: ErrorType {
        .abort
    }

    public var description: String {
        switch self {
        case let .failedToReadFile(path):
            return "Couldn't find file to calculate hash at path \(path.pathString)"
        case let .fileHashingFailed(path):
            return "Couldn't calculate hash of file at path \(path.pathString)"
        case let .stringHashingFailed(string):
            return "Couldn't calculate hash of string \(string) for caching."
        case .dataHashingFailed:
            return "Couldn't get the hash of a data object."
        }
    }
}
