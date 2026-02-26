import Foundation

extension Optional {
    /// Unwraps the optional value or throws the provided error if `nil`.
    ///
    /// - Parameter error: An autoclosure that generates the error to throw if the optional is `nil`.
    /// - Returns: The unwrapped value of the optional.
    /// - Throws: The provided error if the optional is `nil`.
    func throwing(_ error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}
