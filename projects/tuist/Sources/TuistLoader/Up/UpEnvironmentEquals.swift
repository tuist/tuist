import Foundation
import TSCBasic
import TuistSupport

/// Precondition required to succeed setup.
class UpEnvironmentEquals: UpRequired, GraphInitiatable {
    let variable: String
    let value: String

    /// Initializes a Precondition command.
    ///
    /// - Parameters:
    ///   - name: Name of the command.
    ///   - variable: The name of the variable to validate.
    init(name: String,
         variable: String,
         value: String)
    {
        self.variable = variable
        self.value = value
        super.init(name: name)
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath _: AbsolutePath) throws {
        value = try dictionary.get("value")
        variable = try dictionary.get("variable")
        super.init(name: try dictionary.get("name"))
    }

    /// When the command is not met, this method runs it.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Throws: The advice string.
    override func meet(projectPath _: AbsolutePath) throws {
        throw CheckRequirementError.unfulfilled("The variable “$\(variable)” does not equal “\(value)”.")
    }

    /// Returns true when the precondition is met.
    ///
    /// - Parameters
    ///   - projectPath: Path to the directory that contains the project manifest.
    /// - Returns: True if the command doesn't need to be run.
    /// - Throws: An error if the check fails.
    override func isMet(projectPath _: AbsolutePath) throws -> Bool {
        return System.shared.env[variable] == value
    }
}
