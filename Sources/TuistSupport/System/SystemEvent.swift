import Basic
import Foundation
import RxSwift

/// It represents an event sent by a running process.
public enum SystemEvent<T> {
    /// Data sent through the standard output pipe.
    case standardOutput(T)

    /// Data sent through the standard error pipe.
    case standardError(T)

    /// Returns the wrapped value.
    public var value: T {
        switch self {
        case let .standardError(value): return value
        case let .standardOutput(value): return value
        }
    }
}

extension SystemEvent: Equatable where T: Equatable {
    public static func == (lhs: SystemEvent<T>, rhs: SystemEvent<T>) -> Bool {
        switch (lhs, rhs) {
        case let (.standardOutput(lhsValue), .standardOutput(rhsValue)):
            return lhsValue == rhsValue
        case let (.standardError(lhsValue), .standardError(rhsValue)):
            return lhsValue == rhsValue
        default:
            return false
        }
    }
}

extension SystemEvent where T == Data {
    /// Maps the standard output and error from data to string using the utf8 encoding
    func mapToString() -> SystemEvent<String> {
        switch self {
        case let .standardError(data):
            return .standardError(String(data: data, encoding: .utf8)!)
        case let .standardOutput(data):
            return .standardOutput(String(data: data, encoding: .utf8)!)
        }
    }
}
