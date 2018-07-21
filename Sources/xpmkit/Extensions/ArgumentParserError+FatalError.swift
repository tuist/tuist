import Foundation
import Utility
import xpmcore

extension ArgumentParserError: FatalError {
    public var type: ErrorType {
        return .abort
    }
}
