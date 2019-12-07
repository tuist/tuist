import Foundation
import Basic
import TuistCore
import TuistSupport

enum ContentHashingError: FatalError, Equatable {
    case fileNotFound(AbsolutePath)
    case checksumFileFailed(AbsolutePath)
    case checksumStringFailed(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "Couldn't find file at path \(path.pathString)."
        case let .checksumFileFailed(path):
            return "Couldn't calculate checksum for file at path \(path.pathString)."
        case let .checksumStringFailed(string):
            return "Couldn't calculate checksum for string \(string)."
        }
    }

    static func == (lhs: ContentHashingError, rhs: ContentHashingError) -> Bool {
        switch (lhs, rhs) {
        case let (.fileNotFound(lhsPath), .fileNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.checksumFileFailed(lhsPath), .checksumFileFailed(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}
