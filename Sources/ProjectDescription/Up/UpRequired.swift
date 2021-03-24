import Foundation

/// It represents a command that ensures the environment is properly configured, and fails the execution if it is not.
public class UpRequired: Codable, Equatable {
    /// Returns an up that fails the build if the precondition is not met.
    ///
    /// - Parameters
    ///     - advice: A string describing recommended actions to take if the precondition is not met.
    /// - Returns: UpRequired instance to validate assumed preconditions.
    public static func precondition(name: String, advice: String, isMet: [String]) -> UpRequired {
        UpPrecondition(name: name, advice: advice, isMet: isMet)
    }

    public static func == (lhs: UpRequired, rhs: UpRequired) -> Bool {
        lhs.equals(rhs)
    }

    func equals(_: UpRequired) -> Bool {
        fatalError("Subclasses should override this method")
    }
}
