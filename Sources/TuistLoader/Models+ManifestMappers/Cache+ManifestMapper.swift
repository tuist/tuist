import Foundation
import Path
import ProjectDescription
import struct TSCUtility.Version
import TuistSupport
import XcodeGraph

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
