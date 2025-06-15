import Foundation
import ProjectDescription
import TuistSupport

enum CacheProfileError: FatalError, Equatable {
    case invalidVersion(string: String)

    var description: String {
        switch self {
        case let .invalidVersion(string):
            return "Invalid version string \(string)"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidVersion:
            return .abort
        }
    }
}
