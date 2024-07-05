import Foundation
import TuistSupport

enum FullHandleServiceError: FatalError, Equatable {
    case invalidHandle(String)
    var type: ErrorType {
        switch self {
        case .invalidHandle:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .invalidHandle(fullHandle):
            return "The project full handle \(fullHandle) is not in the format of account-handle/project-handle."
        }
    }
}

protocol FullHandleServicing {
    func parse(_ fullHandle: String) throws -> (accountHandle: String, projectHandle: String)
}

final class FullHandleService: FullHandleServicing {
    func parse(_ fullHandle: String) throws -> (accountHandle: String, projectHandle: String) {
        let components = fullHandle.components(separatedBy: "/")
        guard components.count == 2
        else {
            throw FullHandleServiceError.invalidHandle(fullHandle)
        }

        let accountHandle = components[0]
        let projectHandle = components[1]

        return (accountHandle: accountHandle, projectHandle: projectHandle)
    }
}
