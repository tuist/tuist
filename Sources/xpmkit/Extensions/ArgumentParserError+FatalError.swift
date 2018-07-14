import Foundation
import Utility
import xpmcore

extension ArgumentParserError: FatalError {
    /// Error type
    public var type: ErrorType {
        return .abort
    }
}
