import Foundation
import Mockable

public enum FullHandleServiceError: LocalizedError, Equatable {
    case invalidHandle(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidHandle(fullHandle):
            return "The project full handle \(fullHandle) is not in the format of account-handle/project-handle."
        }
    }
}

@Mockable
public protocol FullHandleServicing: Sendable {
    func parse(_ fullHandle: String) throws -> (accountHandle: String, projectHandle: String)
}

public final class FullHandleService: FullHandleServicing {
    public init() {}

    public func parse(_ fullHandle: String) throws -> (accountHandle: String, projectHandle: String) {
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
