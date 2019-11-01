import SPMUtility

// MARK: - FatalError

extension ArgumentParserError: FatalError {
    /// ArgumentParserError has the .abort error type by default.
    public var type: ErrorType {
        return .abort
    }
}
