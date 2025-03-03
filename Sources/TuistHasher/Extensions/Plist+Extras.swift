import Foundation
import XcodeGraph

extension Plist.Value {
    /**
     Normalizes `Plist.Value` into a type from the Swift standard library
     */
    func normalize() -> Any {
        switch self {
        case let .array(array):
            return array.map { $0.normalize() }
        case let .boolean(boolean):
            return boolean
        case let .dictionary(dictionary):
            return dictionary.mapValues { $0.normalize() }
        case let .integer(integer):
            return integer
        case let .real(real):
            return real
        case let .string(string):
            return string
        }
    }
}
