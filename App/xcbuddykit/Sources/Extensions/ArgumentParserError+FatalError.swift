import Foundation
import Utility

extension ArgumentParserError: FatalError {
    /// Error type
    var type: ErrorType {
        return .abort
    }
}
