import Foundation
import TuistCore
import Utility

extension ArgumentParserError: FatalError {
    public var type: ErrorType {
        return .abort
    }
}
