import Foundation
import Utility

extension ShellCompletion: Equatable {
    public static func == (lhs: ShellCompletion, rhs: ShellCompletion) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): fallthrough
        case (.unspecified, .unspecified): fallthrough
        case (.filename, .filename):
            return true
        case let (.function(lhsFunction), .function(rhsFunction)):
            return lhsFunction == rhsFunction
        case let (.values(lhsValues), .values(rhsValues)):
            if lhsValues.count != rhsValues.count { return false }
            for index in 0 ..< lhsValues.count {
                let lhsValue = lhsValues[index]
                let rhsValue = rhsValues[index]
                if lhsValue.description != rhsValue.description || lhsValue.value != rhsValue.value {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}
