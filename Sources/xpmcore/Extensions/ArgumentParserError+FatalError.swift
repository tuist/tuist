import Utility

extension ArgumentParserError: FatalError {
    public var type: ErrorType {
        return .abort
    }
}
