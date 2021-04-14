import Foundation

/// It represents a command that ensures the environment is properly configured, and fails the execution if it is not.
public class UpRequired: Codable, Equatable {
    /// Returns an UpRequired that fails the build if the precondition is not met.
    ///
    /// - Parameters
    ///     - advice: A string describing recommended actions to take if the precondition is not met.
    /// - Returns: UpRequired instance to validate assumed preconditions.
    public static func precondition(name: String, advice: String, isMet: [String]) -> UpRequired {
        UpPrecondition(name: name, advice: advice, isMet: isMet)
    }

    /// Returns a variable matching UpRequired.
    ///
    /// - Parameters:
    ///   - name: Name of the requirement.
    ///   - variable: Environment variable to examine.
    ///   - value: Value that must be assigned to the variable.
    /// - Returns: UpRequirement instance to validate variable’s value.
    public static func variableHasValue(name: String, variable: String, value: String) -> UpRequired {
        UpEnvironmentEquals(name: name, variable: variable, value: value)
    }

    /// Returns a variable detecting UpRequired.
    ///
    /// - Parameters:
    ///   - name: Name of the requirement.
    ///   - variable: Environment variable that must exist.
    /// - Returns: UpRequirement instance to validate variable’s existence.
    public static func variableExists(name: String, variable: String) -> UpRequired {
        UpEnvironmentExists(name: name, variable: variable)
    }

    public static func == (lhs: UpRequired, rhs: UpRequired) -> Bool {
        lhs.equals(rhs)
    }

    func equals(_: UpRequired) -> Bool {
        fatalError("Subclasses should override this method")
    }
}
