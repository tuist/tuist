import Foundation
import TuistCore

enum CarthageError: FatalError {
    case notFound

    var type: ErrorType {
        switch self {
        case .notFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case .notFound:
            return "Carthage not found"
        }
    }
}
