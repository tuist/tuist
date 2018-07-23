import Foundation
import Utility
import TuistCore

extension ArgumentParserError: FatalError {
    public var type: ErrorType {
        return .abort
    }
}
